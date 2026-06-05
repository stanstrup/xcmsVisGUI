# mod_ingest — file selection + asynchronous reading.
#
# Files are added by typing a folder/file path or via the native OS folder
# dialog (utils::choose.dir) — both load in place, no copy (multi-GB safe on a
# local desktop). A native fileInput "Browse files…" is also offered, but it
# copies to a temp dir (documented trade-off). Each file is read in a mirai
# worker via an ExtendedTask, so the UI stays responsive and rows flip from
# "reading" to "ready" one by one. A queue feeds the single-file reader;
# concurrency can be added later by widening the pool of in-flight readers.

mod_ingest_ui <- function(id) {
  ns <- NS(id)
  tagList(
    # 1) paste a folder/file path, or pick a folder server-side — both NO copy
    div(class = "d-flex gap-2 mb-2",
        div(style = "flex:1;",
            textInput(ns("folder"), NULL, width = "100%",
                      placeholder = "Paste a folder or file path…")),
        actionButton(ns("add_folder"), "Add", class = "btn-primary"),
        actionButton(ns("clear"), NULL, icon = icon("trash"),
                     class = "btn-outline-secondary", title = "Clear all files")),
    div(class = "mb-2",
        actionButton(ns("pick_dir"), "Choose folder…", icon = icon("folder-open"),
                     class = "btn-outline-secondary btn-sm")),
    # 2) standard OS file browser (note: copies files to a temp dir)
    fileInput(ns("browse"), NULL, multiple = TRUE,
              accept = c(".mzML", ".mzXML", ".CDF", ".cdf"),
              buttonLabel = "Browse files…", placeholder = "or the OS file browser"),
    helpText("Paste a path or use ‘Choose folder…’ (native OS folder dialog, no copy) ",
             "to load every MS file in a directory — best for many/large files. ",
             "‘Browse files…’ is the OS file dialog but copies files to a temp folder."),
    div(class = "d-flex gap-2 mb-2",
        actionButton(ns("sel_all"),  "All",    class = "btn-sm btn-outline-secondary"),
        actionButton(ns("sel_none"), "None",   class = "btn-sm btn-outline-secondary"),
        actionButton(ns("sel_inv"),  "Invert", class = "btn-sm btn-outline-secondary")),
    helpText("Tick a file to include it in plots. Files stay loaded when unticked."),
    DT::DTOutput(ns("file_table"))
  )
}

mod_ingest_server <- function(id, rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

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

    # --- Add files from any source ----------------------------------------
    add_paths <- function(paths, names = basename(paths)) {
      keep <- !normalizePath(paths, mustWork = FALSE) %in%
        normalizePath(rv$files$path, mustWork = FALSE)
      paths <- paths[keep]; names <- names[keep]
      if (!length(paths)) return(invisible())
      new_rows <- tibble(
        id = paste0("f", as.integer(Sys.time()), "_",
                    seq.int(nrow(rv$files) + 1, length.out = length(paths))),
        path = paths, name = names, sample_group = "group1",
        include = FALSE, status = "reading", n_spectra = NA_integer_,
        rt_min = NA_real_, rt_max = NA_real_, mz_min = NA_real_, mz_max = NA_real_,
        ms_levels = NA_character_, polarities = NA_character_,
        charges = NA_character_, message = NA_character_)
      rv$files <- bind_rows(rv$files, new_rows)
      queue(c(queue(), new_rows$id))
      pump()
    }

    # Pasted folder or file path
    observeEvent(input$add_folder, {
      p <- trimws(input$folder); req(nzchar(p))
      if (dir.exists(p)) {
        fls <- list.files(p, pattern = MS_FILE_REGEX, full.names = TRUE,
                          ignore.case = TRUE)
        if (!length(fls)) showNotification("No MS files found in that folder.",
                                           type = "warning")
        add_paths(fls)
      } else if (file.exists(p)) {
        add_paths(p)
      } else {
        showNotification("Path not found.", type = "error")
      }
      updateTextInput(session, "folder", value = "")
    })

    # Standard OS file browser (Shiny copies the chosen files to temp paths)
    observeEvent(input$browse, {
      up <- input$browse; req(nrow(up) > 0)
      add_paths(up$datapath, names = up$name)
    })

    # Native OS folder dialog (server-side, no copy). Windows: utils::choose.dir().
    observeEvent(input$pick_dir, {
      p <- tryCatch(utils::choose.dir(caption = "Choose a folder of MS files"),
                    error = function(e) NA_character_)
      if (is.null(p) || is.na(p) || !nzchar(p)) return()
      fls <- list.files(p, pattern = MS_FILE_REGEX, full.names = TRUE, ignore.case = TRUE)
      if (!length(fls)) showNotification("No MS files in that folder.", type = "warning")
      add_paths(fls)
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
      clear_ms_caches()
    })

    # --- Render the file list --------------------------------------------
    # Build the display table reactively, but render the widget ONCE and push
    # row updates via a proxy. A full re-render on every async read (140 files!)
    # caused the list to flash empty and was slow.
    disp_df <- reactive({
      f <- rv$files
      cols <- c(" ", "File", "Group", "St", "MS", "Pol")
      if (nrow(f) == 0) {
        empty <- as.data.frame(matrix(character(), 0, length(cols)))
        names(empty) <- cols
        return(empty)
      }
      status_badge <- dplyr::case_when(
        f$status == "ready"   ~ "✅",
        f$status == "reading" ~ "⏳",
        TRUE                  ~ "❌"
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
        ` ` = check, File = f$name, Group = f$sample_group,
        St = status_badge, MS = f$ms_levels, Pol = f$polarities,
        check.names = FALSE, stringsAsFactors = FALSE
      )
    })

    output$file_table <- DT::renderDT({
      isolate(DT::datatable(
        disp_df(), escape = FALSE, rownames = FALSE, selection = "none",
        class = "compact stripe hover", width = "100%",
        editable = list(target = "cell", columns = 2),  # Group editable
        options = list(dom = "t", paging = FALSE, ordering = FALSE, autoWidth = FALSE,
                       language = list(emptyTable = "No files yet."),
                       columnDefs = list(
                         list(className = "dt-center", targets = c(0, 3, 4, 5)),
                         list(width = "22px", targets = c(0, 3)),     # ✓ + status
                         list(width = "auto", targets = 1)))           # File name
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
