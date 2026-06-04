# mod_filter — global rt / m/z / MS level / polarity / intensity filters.
# Controls are built from the combined data ranges of the included files and
# written (debounced) into rv$filter, which the dataset reactive applies.

mod_filter_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("controls")),
    actionButton(ns("reset"), "Reset filters",
                 class = "btn-sm btn-outline-secondary mt-2")
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
      tagList(
        if (!is.null(r$rt))
          sliderInput(ns("rt"), "Retention time (s)",
                      min = floor(r$rt[1]), max = ceiling(r$rt[2]),
                      value = c(floor(r$rt[1]), ceiling(r$rt[2]))),
        if (!is.null(r$mz))
          sliderInput(ns("mz"), "m/z",
                      min = floor(r$mz[1]), max = ceiling(r$mz[2]),
                      value = c(floor(r$mz[1]), ceiling(r$mz[2]))),
        if (length(r$ms_levels) > 1)
          selectInput(ns("ms_level"), "MS level",
                      choices = r$ms_levels, selected = r$ms_levels[1]),
        if (length(r$polarities) > 1)
          selectInput(ns("polarity"), "Polarity",
                      choices = c("any", "pos", "neg"), selected = "any"),
        numericInput(ns("int_min"), "Min intensity", value = 0, min = 0)
      )
    })

    # Debounce so dragging a slider doesn't re-extract on every tick.
    filter_inputs <- reactive({
      list(rt = input$rt, mz = input$mz, ms_level = input$ms_level,
           polarity = input$polarity, int_min = input$int_min)
    }) %>% debounce(600)

    observeEvent(filter_inputs(), {
      fi <- filter_inputs()
      f <- rv$filter
      if (!is.null(fi$rt)) { f$rt_min <- fi$rt[1]; f$rt_max <- fi$rt[2] }
      else { f$rt_min <- NA_real_; f$rt_max <- NA_real_ }
      if (!is.null(fi$mz)) { f$mz_min <- fi$mz[1]; f$mz_max <- fi$mz[2] }
      else { f$mz_min <- NA_real_; f$mz_max <- NA_real_ }
      f$ms_level <- if (!is.null(fi$ms_level)) as.integer(fi$ms_level) else 1L
      f$polarity <- if (!is.null(fi$polarity)) fi$polarity else "any"
      f$int_min  <- if (!is.null(fi$int_min)) fi$int_min else NA_real_
      rv$filter <- f
    }, ignoreNULL = FALSE)

    observeEvent(input$reset, {
      r <- ranges(); req(r)
      if (!is.null(r$rt))
        updateSliderInput(session, "rt", value = c(floor(r$rt[1]), ceiling(r$rt[2])))
      if (!is.null(r$mz))
        updateSliderInput(session, "mz", value = c(floor(r$mz[1]), ceiling(r$mz[2])))
      updateNumericInput(session, "int_min", value = 0)
      if (length(r$polarities) > 1)
        updateSelectInput(session, "polarity", selected = "any")
    })
  })
}
