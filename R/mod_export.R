# mod_export — reusable "Save plot" control: a button that opens a modal with
# a live preview (true output aspect ratio) plus format / size / DPI options
# (seeded from Settings). Static formats + rds download via ggsave/saveRDS; the
# "html" format ships a standalone interactive plotly. Used by every plot module.

mod_export_ui <- function(id, label = "Save") {
  ns <- NS(id)
  actionButton(ns("open"), label, icon = icon("download"),
               class = "btn-sm btn-outline-secondary")
}

# Fit a width x height box (in the chosen units — only the ratio matters) into a
# display box, preserving aspect. Returns integer px so the preview reads as the
# real output would: change Width/Height and the preview re-proportions exactly.
preview_dims <- function(w, h, box = c(560, 460)) {
  if (!is.finite(w) || !is.finite(h) || w <= 0 || h <= 0) { w <- 8; h <- 5 }
  r <- h / w
  dw <- box[1]; dh <- dw * r
  if (dh > box[2]) { dh <- box[2]; dw <- dh / r }
  list(w = round(dw), h = round(dh))
}

#' Apply a zoom_keeper()$ranges value to a ggplot as coordinate limits. NULL per
#' axis means "unzoomed", and coord_cartesian() reads NULL limits as the data
#' range — so a partially zoomed plot needs no special case.
#' @importFrom ggplot2 coord_cartesian
#' @noRd
apply_zoom <- function(p, z) {
  if (is.null(z) || (is.null(z$x) && is.null(z$y))) return(p)
  p + coord_cartesian(xlim = z$x, ylim = z$y)
}

#' @param plot_gg reactive returning the ggplot to save
#' @param rv app reactive store (for default settings)
#' @param basename file stem; a string or a reactive returning one
#' @param zoom optional `zoom_keeper()$ranges` reactive. Given one, the preview
#'   and the saved file are clipped to the plot's CURRENT zoom — you save what
#'   you are looking at, not the full data range.
#' @noRd
mod_export_server <- function(id, plot_gg, rv, basename = "plot", zoom = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    stem <- function() if (is.function(basename)) basename() else basename

    # The single source of truth for both the preview and the download.
    plot_out <- reactive(apply_zoom(plot_gg(), if (is.function(zoom)) zoom() else NULL))

    observeEvent(input$open, {
      s <- rv$settings
      # Interactive HTML needs Pandoc to self-contain; only offer it when present.
      fmts <- c("png", "svg", "pdf", "rds")
      if (has_pandoc()) fmts <- append(fmts, "html", after = 3)
      sel <- if (s$export_format %in% fmts) s$export_format else "png"
      showModal(modalDialog(
        title = "Save plot", size = "l", easyClose = TRUE,
        layout_columns(
          col_widths = c(5, 7),
          # --- controls -----------------------------------------------------
          div(
            selectInput(ns("format"), "Format", fmts, selected = sel),
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
            conditionalPanel(
              sprintf("input['%s'] == 'html'", ns("format")),
              helpText("Standalone interactive plot (zoom/pan/hover). ",
                       "Width/height set the widget size in the page.")
            ),
            conditionalPanel(
              sprintf("input['%s'] == 'rds'", ns("format")),
              helpText("The ggplot object itself — readRDS() to tweak in R.")
            )
          ),
          # --- preview ------------------------------------------------------
          div(
            tags$label(class = "control-label", "Preview"),
            div(class = "border rounded p-1 d-flex justify-content-center align-items-center",
                style = "min-height:200px;background:var(--bs-tertiary-bg)",
                plotOutput(ns("preview"), width = "auto", height = "auto")),
            helpText("True aspect ratio of the file; on-screen DPI only.")
          )
        ),
        footer = tagList(modalButton("Cancel"),
                         downloadButton(ns("download"), "Download",
                                        class = "btn-primary"))
      ))
    })

    # Re-proportion the preview as Width/Height change (debounced so it doesn't
    # re-render on every keystroke). Rendering the actual ggplot — not the plotly
    # — is what makes the preview faithful to the exported png/svg/pdf.
    pdims <- debounce(reactive(preview_dims(input$width, input$height)), 250)
    output$preview <- renderPlot(plot_out(),
                                 width  = function() pdims()$w,
                                 height = function() pdims()$h)

    output$download <- downloadHandler(
      filename = function() sprintf("%s.%s", stem(), input$format),
      content = function(file) {
        on.exit(removeModal())
        save_gg(plot_out(), file, list(
          export_format = input$format, export_width = input$width,
          export_height = input$height, export_units = input$units,
          export_dpi = input$dpi, export_title = stem()))
      }
    )
  })
}
