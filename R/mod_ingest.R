# mod_ingest — file selection + asynchronous reading.
#
# Files are picked server-side with shinyFiles (no upload; multi-GB safe on a
# local desktop). Each file is read in a mirai worker via an ExtendedTask, so
# the UI stays responsive and rows flip from "reading" to "ready" one by one.
# A queue feeds the single-file reader; concurrency can be added later by
# widening the pool of in-flight readers.

mod_ingest_ui <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "d-flex gap-2 mb-2",
      shinyFilesButton(
        ns("files"), "Add files…", "Select MS data files",
        multiple = TRUE, icon = icon("folder-open"), class = "btn-primary"
      ),
      actionButton(ns("clear"), "Clear", icon = icon("trash"),
                   class = "btn-outline-secondary")
    ),
    div(
      class = "d-flex gap-2 mb-2",
      actionButton(ns("sel_all"),  "All",    class = "btn-sm btn-outline-secondary"),
      actionButton(ns("sel_none"), "None",   class = "btn-sm btn-outline-secondary"),
      actionButton(ns("sel_inv"),  "Invert", class = "btn-sm btn-outline-secondary")
    ),
    helpText("Tick a file to include it in plots. Files stay loaded when unticked."),
    DT::DTOutput(ns("file_table"))
  )
}

mod_ingest_server <- function(id, rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- shinyFiles wiring ------------------------------------------------
    roots <- c(Home = fs::path_home(), getVolumes()())
    shinyFileChoose(input, "files", roots = roots, session = session,
                    filetypes = MS_FILE_EXTS)

    # --- Read queue + single-file async reader ----------------------------
    queue <- reactiveVal(character())     # file ids waiting to be read
    current <- reactiveVal(NULL)          # file id currently being read

    reader <- ExtendedTask$new(function(path) {
      mirai::mirai(
        read_ms_header(path),
        read_ms_header = read_ms_header,
        path = path
      )
    })

    # Kick the next queued file into the reader if it is idle.
    pump <- function() {
      if (reader$status() == "running") return(invisible())
      q <- queue()
      if (length(q) == 0) { current(NULL); return(invisible()) }
      id <- q[1]
      queue(q[-1])
      current(id)
      path <- rv$files$path[rv$files$id == id]
      reader$invoke(path = path)
    }

    # --- Add picked files to the table as "reading" -----------------------
    observeEvent(input$files, {
      parsed <- parseFilePaths(roots, input$files)
      req(nrow(parsed) > 0)
      paths <- as.character(parsed$datapath)
      paths <- paths[!normalizePath(paths) %in% normalizePath(rv$files$path)]
      req(length(paths) > 0)

      new_rows <- tibble(
        id = paste0("f", as.integer(Sys.time()), "_", seq_along(paths)),
        path = paths,
        name = basename(paths),
        sample_group = "group1",
        include = TRUE,
        status = "reading",
        n_spectra = NA_integer_,
        rt_min = NA_real_, rt_max = NA_real_,
        mz_min = NA_real_, mz_max = NA_real_,
        ms_levels = NA_character_, polarities = NA_character_,
        charges = NA_character_, message = NA_character_
      )
      rv$files <- bind_rows(rv$files, new_rows)
      queue(c(queue(), new_rows$id))
      pump()
    })

    # --- Reader finished: update the row, then pump the next --------------
    observeEvent(reader$status(), {
      st <- reader$status()
      if (!st %in% c("success", "error")) return()
      id <- current()
      if (is.null(id)) return()
      idx <- which(rv$files$id == id)

      if (st == "error") {
        rv$files$status[idx] <- "error"
        rv$files$message[idx] <- "read failed"
      } else {
        res <- reader$result()
        if (!is.null(res$error)) {
          rv$files$status[idx] <- "error"
          rv$files$message[idx] <- res$error
        } else {
          s <- res$summary
          rv$files$status[idx]    <- "ready"
          rv$files$n_spectra[idx] <- s$n_spectra
          rv$files$rt_min[idx]    <- s$rt_min
          rv$files$rt_max[idx]    <- s$rt_max
          rv$files$mz_min[idx]    <- s$mz_min
          rv$files$mz_max[idx]    <- s$mz_max
          rv$files$ms_levels[idx]  <- s$ms_levels
          rv$files$polarities[idx] <- polarity_label(s$polarities)
          rv$files$charges[idx]    <- s$charges %||% NA_character_
        }
      }
      current(NULL)
      pump()
    })

    # --- Include/exclude controls ----------------------------------------
    observeEvent(input$sel_all,  if (nrow(rv$files)) rv$files$include <- TRUE)
    observeEvent(input$sel_none, if (nrow(rv$files)) rv$files$include <- FALSE)
    observeEvent(input$sel_inv,  if (nrow(rv$files)) rv$files$include <- !rv$files$include)
    observeEvent(input$clear, {
      rv$files <- rv$files[0, ]
      queue(character()); current(NULL)
    })

    # --- Render the file list --------------------------------------------
    # Build the display table reactively, but render the widget ONCE and push
    # row updates via a proxy. A full re-render on every async read (140 files!)
    # caused the list to flash empty and was slow.
    disp_df <- reactive({
      f <- rv$files
      cols <- c("Include", "File", "Group", "Status", "Spectra",
                "RT range", "MS levels", "Polarity")
      if (nrow(f) == 0) {
        empty <- as.data.frame(matrix(character(), 0, length(cols)))
        names(empty) <- cols
        return(empty)
      }
      status_badge <- dplyr::case_when(
        f$status == "ready"   ~ "✅ ready",
        f$status == "reading" ~ "⏳ reading",
        TRUE                  ~ "❌ error"
      )
      check <- vapply(seq_len(nrow(f)), function(i) {
        as.character(tags$input(
          type = "checkbox", checked = if (f$include[i]) "checked" else NULL,
          onclick = sprintf(
            "Shiny.setInputValue('%s', {id: '%s', checked: this.checked}, {priority:'event'})",
            ns("toggle"), f$id[i])
        ))
      }, character(1))
      data.frame(
        Include = check, File = f$name, Group = f$sample_group,
        Status = status_badge, Spectra = f$n_spectra,
        `RT range` = ifelse(is.na(f$rt_min), "",
                            sprintf("%.0f–%.0f", f$rt_min, f$rt_max)),
        `MS levels` = f$ms_levels, Polarity = f$polarities,
        check.names = FALSE, stringsAsFactors = FALSE
      )
    })

    output$file_table <- DT::renderDT({
      isolate(DT::datatable(
        disp_df(), escape = FALSE, rownames = FALSE, selection = "none",
        editable = list(target = "cell", columns = 2),  # Group editable
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       language = list(emptyTable = "No files yet — click “Add files…”."),
                       columnDefs = list(list(className = "dt-center",
                                              targets = c(0, 3, 4))))
      ))
    })
    file_proxy <- DT::dataTableProxy("file_table")
    observeEvent(disp_df(), {
      DT::replaceData(file_proxy, disp_df(), rownames = FALSE, resetPaging = FALSE)
    }, ignoreInit = TRUE)

    # Checkbox toggles
    observeEvent(input$toggle, {
      idx <- which(rv$files$id == input$toggle$id)
      if (length(idx)) rv$files$include[idx] <- isTRUE(input$toggle$checked)
    })
    # Sample group edits
    observeEvent(input$file_table_cell_edit, {
      info <- input$file_table_cell_edit
      if (identical(as.integer(info$col), 2L)) {
        rv$files$sample_group[info$row] <- as.character(info$value)
      }
    }, ignoreInit = TRUE)
  })
}
