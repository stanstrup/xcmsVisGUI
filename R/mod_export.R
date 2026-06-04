# mod_export — reusable "Save plot" control: a button that opens a modal with
# format / size / DPI options (seeded from Settings) and downloads via ggsave.
# Used by every ggplot-based plot module.

mod_export_ui <- function(id, label = "Save") {
  ns <- NS(id)
  actionButton(ns("open"), label, icon = icon("download"),
               class = "btn-sm btn-outline-secondary")
}

#' @param plot_gg reactive returning the ggplot to save
#' @param rv app reactive store (for default settings)
#' @param basename file stem; a string or a reactive returning one
mod_export_server <- function(id, plot_gg, rv, basename = "plot") {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    stem <- function() if (is.function(basename)) basename() else basename

    observeEvent(input$open, {
      s <- rv$settings
      showModal(modalDialog(
        title = "Save plot", size = "m", easyClose = TRUE,
        selectInput(ns("format"), "Format", c("png", "svg", "pdf"),
                    selected = s$export_format),
        layout_columns(
          col_widths = c(4, 4, 4),
          numericInput(ns("width"),  "Width",  s$export_width,  min = 1),
          numericInput(ns("height"), "Height", s$export_height, min = 1),
          selectInput(ns("units"),   "Units",  c("in", "cm", "mm", "px"),
                      selected = s$export_units)
        ),
        conditionalPanel(
          sprintf("input['%s'] == 'png'", ns("format")),
          numericInput(ns("dpi"), "DPI", s$export_dpi, min = 36, max = 1200)
        ),
        footer = tagList(modalButton("Cancel"),
                         downloadButton(ns("download"), "Download",
                                        class = "btn-primary"))
      ))
    })

    output$download <- downloadHandler(
      filename = function() sprintf("%s.%s", stem(), input$format),
      content = function(file) {
        on.exit(removeModal())
        save_gg(plot_gg(), file, list(
          export_format = input$format, export_width = input$width,
          export_height = input$height, export_units = input$units,
          export_dpi = input$dpi))
      }
    )
  })
}
