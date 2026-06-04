# mod_filter — global rt / m/z / MS level / polarity / intensity filters.
# Typed numeric inputs (blank = no constraint). rt inputs are in the display
# unit and stored in seconds; everything is written (debounced) to rv$filter.

mod_filter_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("controls")),
    actionButton(ns("reset"), "Reset filters",
                 class = "btn-sm btn-outline-secondary mt-2")
  )
}

# numeric min/max pair on one row, with a range hint
.minmax <- function(ns, key, label, hint, step) {
  tagList(
    tags$label(class = "control-label", label),
    if (nzchar(hint)) tags$small(class = "text-muted d-block", hint),
    div(class = "d-flex gap-2",
        numericInput(ns(paste0(key, "_min")), NULL, value = NA, step = step, width = "100%"),
        numericInput(ns(paste0(key, "_max")), NULL, value = NA, step = step, width = "100%"))
  )
}

mod_filter_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    ranges <- reactive({
      inc <- included()
      if (nrow(inc) == 0) return(NULL)
      combined_ranges(inc)
    })

    output$controls <- renderUI({
      r <- ranges()
      if (is.null(r))
        return(helpText("Load and include files to enable filters."))
      unit <- rv$settings$time_unit
      rt_hint <- if (!is.null(r$rt))
        sprintf("data: %.2f–%.2f %s", rt_to_disp(r$rt[1], unit),
                rt_to_disp(r$rt[2], unit), unit) else ""
      mz_hint <- if (!is.null(r$mz))
        sprintf("data: %.4f–%.4f", r$mz[1], r$mz[2]) else ""
      tagList(
        .minmax(ns, "rt", sprintf("Retention time (%s)", unit), rt_hint, 0.01),
        .minmax(ns, "mz", "m/z", mz_hint, 0.0001),
        .minmax(ns, "int", "Intensity", "", 1),
        selectInput(ns("ms_level"), "MS level",
                    choices = c("all", r$ms_levels),
                    selected = if ("1" %in% r$ms_levels) "1" else "all"),
        selectInput(ns("polarity"), "Polarity",
                    choices = c("any", "pos", "neg"), selected = "any"),
        textInput(ns("spectrum_id"), "Spectrum ID contains",
                  placeholder = "e.g. function=1 process=0"),
        helpText("Leave a box blank for no limit.")
      )
    })

    filter_inputs <- reactive({
      list(rt_min = input$rt_min, rt_max = input$rt_max,
           mz_min = input$mz_min, mz_max = input$mz_max,
           int_min = input$int_min, int_max = input$int_max,
           ms_level = input$ms_level, polarity = input$polarity,
           spectrum_id = input$spectrum_id)
    }) %>% debounce(600)

    observeEvent(filter_inputs(), {
      fi <- filter_inputs()
      unit <- rv$settings$time_unit
      num <- function(v) if (is.null(v) || !is.finite(v)) NA_real_ else v
      f <- rv$filter
      f$rt_min <- rt_to_sec(num(fi$rt_min), unit)
      f$rt_max <- rt_to_sec(num(fi$rt_max), unit)
      f$mz_min <- num(fi$mz_min); f$mz_max <- num(fi$mz_max)
      f$int_min <- num(fi$int_min); f$int_max <- num(fi$int_max)
      f$ms_level <- if (is.null(fi$ms_level) || identical(fi$ms_level, "all"))
                      NA_integer_ else as.integer(fi$ms_level)
      f$polarity <- if (!is.null(fi$polarity)) fi$polarity else "any"
      f$spectrum_id <- fi$spectrum_id %||% ""
      rv$filter <- f
    }, ignoreNULL = FALSE)

    observeEvent(input$reset, {
      for (k in c("rt_min","rt_max","mz_min","mz_max","int_min","int_max"))
        updateNumericInput(session, k, value = NA)
      updateTextInput(session, "spectrum_id", value = "")
      updateSelectInput(session, "polarity", selected = "any")
    })
  })
}
