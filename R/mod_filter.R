# mod_filter — global rt / m/z / MS level / polarity / intensity filters.
# Typed numeric inputs (blank = no constraint). rt inputs are in the display
# unit and stored in seconds; everything is written (debounced) to rv$filter.

mod_filter_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("controls")),
    # Spectrum-ID rules. Each row is contains/exclude + a fixed-string term;
    # contains-rows are ANDed (id must contain the term), exclude-rows require it
    # absent. Rows are added/removed with insertUI/removeUI so the others keep
    # their typed values.
    tags$hr(class = "my-2"),
    tags$label(class = "control-label", "Spectrum ID"),
    tags$small(class = "text-muted d-block mb-1",
               "Match the raw spectrum id (e.g. function=1). ",
               "Add rows to require or exclude terms."),
    div(id = ns("id_rules")),
    actionButton(ns("id_add"), "Add rule", icon = icon("plus"),
                 class = "btn-sm btn-outline-primary"),
    actionButton(ns("reset"), "Reset filters",
                 class = "btn-sm btn-outline-secondary mt-2 d-block")
  )
}

# numeric min/max pair on one row, with a range hint. `vmin`/`vmax` seed the
# boxes: the panel is re-rendered whenever the included files change (the hints
# and MS-level choices are data-derived), so the caller passes the CURRENT values
# back in — otherwise every re-render would blank the user's typed filter.
.minmax <- function(ns, key, label, hint, step, vmin = NA, vmax = NA) {
  tagList(
    tags$label(class = "control-label", label),
    if (nzchar(hint)) tags$small(class = "text-muted d-block", hint),
    div(class = "d-flex gap-2",
        numericInput(ns(paste0(key, "_min")), NULL, value = vmin, step = step, width = "100%"),
        numericInput(ns(paste0(key, "_max")), NULL, value = vmax, step = step, width = "100%"))
  )
}

mod_filter_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- Spectrum-ID rules (dynamic rows) --------------------------------
    rule_ids <- reactiveVal(character())   # rids currently shown
    rule_seq <- reactiveVal(0L)            # monotonic counter for unique ids

    rule_row <- function(rid) {
      div(id = ns(paste0("id_row_", rid)),
          class = "d-flex gap-1 mb-1 align-items-center",
          div(style = "flex:0 0 90px",
              selectInput(ns(paste0("id_mode_", rid)), NULL, width = "100%",
                          choices = c("contains", "exclude"), selectize = FALSE)),
          div(style = "flex:1",
              textInput(ns(paste0("id_text_", rid)), NULL, width = "100%",
                        placeholder = "function=1")),
          tags$button(icon("xmark"), type = "button", title = "Remove rule",
                      class = "btn btn-sm btn-outline-secondary",
                      onclick = sprintf(
                        "Shiny.setInputValue('%s', '%s', {priority:'event'})",
                        ns("id_remove"), rid)))
    }

    observeEvent(input$id_add, {
      rule_seq(rule_seq() + 1L)
      rid <- paste0("r", rule_seq())
      rule_ids(c(rule_ids(), rid))
      insertUI(paste0("#", ns("id_rules")), "beforeEnd", rule_row(rid), immediate = TRUE)
    })

    observeEvent(input$id_remove, {
      rid <- input$id_remove
      removeUI(paste0("#", ns(paste0("id_row_", rid))), immediate = TRUE)
      rule_ids(setdiff(rule_ids(), rid))
    })

    ranges <- reactive({
      inc <- included()
      if (nrow(inc) == 0) return(NULL)
      combined_ranges(inc)
    })

    # The panel is rebuilt whenever the included files change, because the range
    # hints and the MS-level choices are read off the data. That rebuild used to
    # RESET every control \u2014 including files then silently cleared the filter the
    # user had typed. So each control is re-seeded from its own current value
    # (isolated: this must not make the panel re-render on every keystroke).
    keep <- function(id, default = NA) isolate(input[[id]]) %||% default
    output$controls <- renderUI({
      r <- ranges()
      if (is.null(r))
        return(helpText("Load and include files to enable filters."))
      unit <- rv$settings$time_unit
      rt_hint <- if (!is.null(r$rt))
        sprintf("data: %.2f\u2013%.2f %s", rt_to_disp(r$rt[1], unit),
                rt_to_disp(r$rt[2], unit), unit) else ""
      mz_hint <- if (!is.null(r$mz))
        sprintf("data: %.4f\u2013%.4f", r$mz[1], r$mz[2]) else ""
      # A previously chosen MS level is kept only while the new file set still
      # offers it; otherwise fall back to the usual default.
      ms_now <- keep("ms_level", NULL)
      ms_sel <- if (!is.null(ms_now) && ms_now %in% c("all", r$ms_levels)) ms_now
                else if ("1" %in% r$ms_levels) "1" else "all"
      tagList(
        .minmax(ns, "rt", sprintf("Retention time (%s)", unit), rt_hint, 0.01,
                keep("rt_min"), keep("rt_max")),
        .minmax(ns, "mz", "m/z", mz_hint, 0.0001, keep("mz_min"), keep("mz_max")),
        .minmax(ns, "int", "Intensity", "", 1, keep("int_min"), keep("int_max")),
        div(class = "d-flex gap-2",
            div(style = "flex:1",
                selectInput(ns("ms_level"), "MS level", width = "100%",
                            choices = c("all", r$ms_levels), selected = ms_sel)),
            div(style = "flex:1",
                selectInput(ns("polarity"), "Polarity", width = "100%",
                            choices = c("any", "pos", "neg"),
                            selected = keep("polarity", "any")))),
        helpText("Leave a box blank for no limit.")
      )
    })

    filter_inputs <- reactive({
      rules <- lapply(rule_ids(), function(rid) list(
        mode = input[[paste0("id_mode_", rid)]] %||% "contains",
        text = input[[paste0("id_text_", rid)]] %||% ""))
      list(rt_min = input$rt_min, rt_max = input$rt_max,
           mz_min = input$mz_min, mz_max = input$mz_max,
           int_min = input$int_min, int_max = input$int_max,
           ms_level = input$ms_level, polarity = input$polarity,
           spectrum_id_rules = rules)
    }) %>% debounce(600)

    # Only write rv$filter when the composed filter actually CHANGES. The filter
    # controls (uiOutput) render lazily the first time the Filters section is
    # opened; that render initialises the inputs and fires this observer with a
    # filter equal to the current one. Reassigning an equal value would still
    # invalidate data_key() and needlessly re-extract every chromatogram — the
    # "TIC redraws when I open Filters" symptom. Skip the no-op assignment.
    observeEvent(filter_inputs(), {
      f <- make_filter(filter_inputs(), rv$settings$time_unit)
      if (!identical(rv$filter, f)) rv$filter <- f
    }, ignoreNULL = FALSE)

    observeEvent(input$reset, {
      for (k in c("rt_min","rt_max","mz_min","mz_max","int_min","int_max"))
        updateNumericInput(session, k, value = NA)
      for (rid in rule_ids())
        removeUI(paste0("#", ns(paste0("id_row_", rid))), immediate = TRUE)
      rule_ids(character())
      updateSelectInput(session, "polarity", selected = "any")
      updateSelectInput(session, "ms_level",
        selected = if ("1" %in% ranges()$ms_levels) "1" else "all")
    })
  })
}
