# mod_ingest — file selection + asynchronous reading.
#
# Files are added by typing a folder/file path or via the native OS folder
# dialog (utils::choose.dir) — both load in place, no copy (multi-GB safe on a
# local desktop). A native fileInput "Browse files…" is also offered, but it
# copies to a temp dir (documented trade-off). Each file is read in a mirai
# worker via an ExtendedTask, so the UI stays responsive and rows flip from
# "reading" to "ready" one by one. A queue feeds the single-file reader;
# concurrency can be added later by widening the pool of in-flight readers.

#' @importFrom DT DTOutput
#' @noRd
mod_ingest_ui <- function(id) {
  ns <- NS(id)
  info <- function(txt)
    bslib::tooltip(icon("circle-info", class = "text-muted ms-1"), txt, placement = "right")
  # All/None/Invert manipulate the DT row selection *client-side* via the
  # binding's own shinyMethods (reliable; the server->client selectRows message
  # is flaky for empty sets and races with async redraws). The selection change
  # then flows back to the server through the normal rows_selected event.
  tid <- ns("file_table")
  sel_js <- function(mode) sprintf(paste0(
    "var t=$('#%s').data('datatable'); if(t&&t.shinyMethods){",
    "var n=t.rows().count(),a=[];for(var i=1;i<=n;i++)a.push(i);",
    "var c=t.rows('.selected').indexes().toArray().map(function(i){return i+1;});",
    "t.shinyMethods.selectRows(%s);}"),
    tid,
    switch(mode,
           all = "a", none = "[]",
           inv = "a.filter(function(x){return c.indexOf(x)<0;})"))
  tagList(
    # Compact file table: small text, tight padding, one-line File names (truncated,
    # full name on hover) so the list stays short and never scrolls horizontally.
    tags$style(HTML(sprintf(paste0(
      "#%s td,#%s th{padding:1px 4px;font-size:12px;white-space:nowrap} ",
      "#%s .fname{display:block;max-width:115px;overflow:hidden;",
      "text-overflow:ellipsis;white-space:nowrap}"),
      ns("file_table"), ns("file_table"), ns("file_table")))),
    # 1) paste a folder/file path, or pick a folder server-side — both NO copy
    div(class = "d-flex gap-2 mb-1",
        div(style = "flex:1;",
            textInput(ns("folder"), NULL, width = "100%",
                      placeholder = "Paste a folder or file path\u2026")),
        actionButton(ns("add_folder"), "Add", class = "btn-primary"),
        actionButton(ns("clear"), NULL, icon = icon("trash"),
                     class = "btn-outline-secondary", title = "Clear all files")),
    div(class = "d-flex gap-2 mb-1 align-items-center",
        actionButton(ns("pick_dir"), "Choose folder\u2026", icon = icon("folder-open"),
                     class = "btn-outline-secondary btn-sm"),
        info(paste0("Paste a path or use \u2018Choose folder\u2026\u2019 (native OS folder ",
                    "dialog, no copy) to load every MS file in a directory \u2014 best for ",
                    "many/large files. \u2018Browse files\u2026\u2019 is the OS file dialog but ",
                    "copies files to a temp folder."))),
    # 2) standard OS file browser (note: copies files to a temp dir)
    fileInput(ns("browse"), NULL, multiple = TRUE,
              accept = c(".mzML", ".mzXML", ".CDF", ".cdf"),
              buttonLabel = "Browse files\u2026", placeholder = "or the OS file browser"),
    div(class = "d-flex gap-2 mb-1 align-items-center",
        tags$button("All",    type = "button", class = "btn btn-sm btn-outline-secondary",
                    onclick = sel_js("all")),
        tags$button("None",   type = "button", class = "btn btn-sm btn-outline-secondary",
                    onclick = sel_js("none")),
        tags$button("Invert", type = "button", class = "btn btn-sm btn-outline-secondary",
                    onclick = sel_js("inv")),
        info(paste0("Click a row to include that file in plots; click again to ",
                    "exclude. Files stay loaded when excluded. Double-click the ",
                    "Group cell to rename its sample group."))),
    DTOutput(ns("file_table"))
  )
}

#' @importFrom mirai mirai
#' @importFrom tibble tibble
#' @importFrom dplyr bind_rows case_when
#' @importFrom DT renderDT datatable dataTableProxy replaceData
#' @noRd
mod_ingest_server <- function(id, rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- Read queue + single-file async reader ----------------------------
    queue <- reactiveVal(character())     # file ids waiting to be read
    current <- reactiveVal(NULL)          # file id currently being read

    reader <- ExtendedTask$new(function(path) {
      mirai(
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

    # Native OS folder dialog (server-side, no copy). choose.dir() is Windows-only
    # and not exported by utils elsewhere, so fetch it dynamically (a static
    # utils::choose.dir would fail load / R CMD check on non-Windows).
    observeEvent(input$pick_dir, {
      choose_dir <- get0("choose.dir", envir = asNamespace("utils"))
      if (is.null(choose_dir)) {
        showNotification("Folder dialog is Windows-only; paste a path instead.",
                         type = "warning")
        return()
      }
      p <- tryCatch(choose_dir(caption = "Choose a folder of MS files"),
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

    # --- Clear-all -------------------------------------------------------
    # (All/None/Invert are handled client-side in the UI; see mod_ingest_ui.)
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
      cols <- c("File", "Group", "St", "MS", "Pol")
      if (nrow(f) == 0) {
        empty <- as.data.frame(matrix(character(), 0, length(cols)))
        names(empty) <- cols
        return(empty)
      }
      status_badge <- case_when(
        f$status == "ready"   ~ "\u2705",
        f$status == "reading" ~ "\u23f3",
        TRUE                  ~ "\u274c"
      )
      # File name truncated to one line (full name on hover) so long names neither
      # wrap into tall rows nor force the sidebar to scroll.
      fname <- vapply(f$name, function(nm)
        as.character(tags$span(class = "fname", title = nm, nm)), character(1))
      data.frame(
        File = fname, Group = f$sample_group,
        St = status_badge, MS = f$ms_levels, Pol = f$polarities,
        check.names = FALSE, stringsAsFactors = FALSE
      )
    })

    output$file_table <- renderDT({
      isolate(datatable(
        disp_df(), escape = FALSE, rownames = FALSE,
        selection = list(mode = "multiple", selected = which(rv$files$include),
                         target = "row"),
        class = "compact stripe hover", width = "100%",
        editable = list(target = "cell", columns = 1),  # Group editable
        options = list(dom = "t", paging = FALSE, ordering = FALSE, autoWidth = FALSE,
                       language = list(emptyTable = "No files yet."),
                       columnDefs = list(
                         list(className = "dt-center", targets = c(2, 3, 4)),
                         list(width = "22px", targets = 2),            # status
                         list(width = "auto", targets = 0)))           # File name
      ))
    })
    file_proxy <- dataTableProxy("file_table")
    # Push row updates ONLY when the displayed content changes. disp_df() carries
    # no include column, so toggling inclusion leaves it identical and skips the
    # replaceData — otherwise that redraw would race with the client-side
    # selection changes and scramble the row selection.
    last_disp <- reactiveVal(NULL)
    observeEvent(disp_df(), {
      cur <- disp_df()
      if (identical(cur, last_disp())) return()
      last_disp(cur)
      replaceData(file_proxy, cur, rownames = FALSE, resetPaging = FALSE,
                  clearSelection = "none")
    }, ignoreInit = TRUE)

    # --- Selection drives inclusion --------------------------------------
    # The selected rows ARE the included files: clicking a row (de)selects it,
    # and this observer is the single writer of $include. The All/None/Invert
    # buttons reach $include only by re-selecting rows on the client, so there
    # is one source of truth and no feedback loop.
    observeEvent(input$file_table_rows_selected, {
      want <- seq_len(nrow(rv$files)) %in% input$file_table_rows_selected
      if (!identical(want, rv$files$include)) rv$files$include <- want
    }, ignoreNULL = FALSE, ignoreInit = TRUE)

    # Sample group edits (Group is now display column 1)
    observeEvent(input$file_table_cell_edit, {
      info <- input$file_table_cell_edit
      if (identical(as.integer(info$col), 1L)) {
        rv$files$sample_group[info$row] <- as.character(info$value)
      }
    }, ignoreInit = TRUE)
  })
}
