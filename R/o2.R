ro2_ui <- miniPage(
  gadgetTitleBar("O2 Assistant", left = NULL),
  miniTabstripPanel(
    miniTabPanel(
      "Login", icon = icon("user"),
      miniContentPanel(
        fillRow(flex = c(1, 1, 1, 1), height = "50px",
                uiOutput("o2id"),
                uiOutput("remote"),
                uiOutput("local"),
                uiOutput("execute")),
        hr(),
        h4("On your local machine:"),
        h5("Login"), sendTermOutput("login"),
        h5("Mount Folder"), sendTermOutput("mount"),
        h5("Unmount Folder"), sendTermOutput("unmount")
      )
    ),
    miniTabPanel(
      "Run", icon = icon("paper-plane"),
      miniContentPanel(
        fillRow(flex = c(1, 1, 1), height = "60px",
                uiOutput("partition"),
                uiOutput("duration"),
                uiOutput("mem")),
        fillRow(flex = c(1, 1, 1, 1, 1), height = "60px",
                uiOutput("n"),
                uiOutput("c"),
                uiOutput("N"),
                uiOutput("o"),
                uiOutput("gpu")),
        hr(),
        h4("On O2 server:"),
        h5("Interactive Session"),
        sendTermOutput("run_int"),
        tags$div(
          h5("Batch Run", style = "float: left;"),
          tags$div(
            style = "float: right;",
            shinyFilesButton("file", "Select Script", "Select batch script" , FALSE)
          )
        ),
        sendTermOutput("run_batch"),
        actionButton("check_batch", "Check Batch Job Status", icon("chalkboard")),
        hr(),
        radioGroupButtons(
          inputId = "module", label = "Module Related",
          choices = c("Search possible modules" = "spider",
                      "List loaded modules" = "list",
                      "Save current setups" = "s",
                      "Restore saved setups" = "r")
        ),
        sendTermOutput("run_module")
      )
    ),
    miniTabPanel(
      "ssh-keygen", icon = icon("lock"),
      miniContentPanel(
        h4("On your local machine:"),
        h5("1. Generate ssh RSA key"),
        fillRow(
          flex = c(6, 2), height = "70px",
          tagList(
            p("Follow instruction on the screen and create a set of ssh RSA keys (private & public)."),
            p("Do not enter any passphrase for passwordless login. ")
          ),
          div(style = "min-width: 160px;",
              textInput("sshkey_file", "Enter sshkey file name", "id_rsa", width = "100%"))
        ),
        sendTermOutput("run_sshkeygen"),
        h5("2. Setup ssh key config file"),
        p("Put something like below in ~/.ssh/config. Make changes to the last line if necessary."),
        fillRow(
          flex = c(7, 1), height = "100px",
          verbatimTextOutput("sshkey_config"), uiOutput("sshkey_config_btn")
        ),
        h5("3. Copy the ssh pub key file to the O2 server & login"),
        sendTermOutput("run_sshkey_scp"),
        sendTermOutput("run_ssh_login"),
        hr(),
        h4("On O2 server:"),
        h5("4. Put pub key into authorized_keys file"),
        fillRow(
          flex = c(7, 1), height = "180px",
          uiOutput("sshkey_auth"),
          uiOutput("sshkey_auth_btn")
        )

      )
    )
  )
)

ro2_server <- function(input, output, session) {
  observeEvent(input$done, {
    invisible(stopApp())
  })

  # Login =====================================================================

  if (file.exists("~/.o2meta")) {
    init_meta <- readLines("~/.o2meta")
  } else {
    init_meta <- c("", "~", "~/o2_home")
  }

  if (length(rstudioapi::terminalList()) != 0) {
    terms <- rstudioapi::terminalList()
    term_caption <- sapply(terms, function(x){terminalContext(x)["caption"]})
    if ("O2" %in% term_caption) {
      term_id <- terms[term_caption == "O2"]
    } else {
      term_id <- rstudioapi::terminalCreate(caption = "O2")
    }
  } else {
    term_id <- rstudioapi::terminalCreate()
  }
  rstudioapi::terminalActivate(term_id)


  output$execute <- renderUI({
    tags$div(
      # actionButton("create_local", "Create Dir"),
      style = "margin-top: 35px; ",
      materialSwitch(
        "exec", "Execute", value = T, status = "primary"
      )
    )
  })

  output$o2id <- renderUI({
    textInput(
      "o2id", "eCommons ID", value = init_meta[1], width = "95%"
    )
  })

  output$remote <- renderUI({
    textInput(
      "remote", "Remote Folder", value = init_meta[2], width = "95%"
    )
  })

  output$local <- renderUI({
    textInput(
      "local", "Local Folder", value = init_meta[3], width = "95%"
    )
  })

  meta <- reactive({
    req(input$remote)
    if (input$remote == "~") {
      remote <- paste0("/home/", input$o2id)
    } else {
      remote <- input$remote
    }
    c(input$o2id, remote, input$local, term_id)
  })

  observeEvent(meta(), writeLines(meta(), "~/.o2meta"))

  meta_login <- reactive({
    paste0("ssh ", input$o2id, "@o2.hms.harvard.edu")
  })

  code_exec <- reactive({input$exec})

  callModule(sendTerm, "login", code = meta_login, term_id = term_id,
             execute = code_exec)

  meta_mount <- reactive({
    if (Sys.info()[["sysname"]] == "Darwin") {
      extra_options <- paste0(
        ",defer_permissions,noappledouble,negative_vncache,volname=",
        basename(input$local)
      )
    } else {
      extra_options <- ""
    }
    paste0("sshfs -p 22 ", input$o2id, "@o2.hms.harvard.edu:",
           meta()[2], " ", input$local,
           " -oauto_cache", extra_options)
  })

  callModule(sendTerm, "mount", code = meta_mount, term_id = term_id,
             execute = code_exec)

  meta_unmount <- reactive({
    if (Sys.info()[["sysname"]] == "Darwin") {
      paste("umount", input$local)
    } else {
      paste("fusermount -u", input$local)
    }
  })

  callModule(sendTerm, "unmount", code = meta_unmount, term_id = term_id)

  # Run =======================================================================

  if (file.exists("~/.o2job")) {
    init_job <- readLines("~/.o2job")
  } else {
    init_job <- c("short", "0-03:00:00", "2G", "", "", "", "", "1")
  }

  output$partition <- renderUI({
    selectInput(
      "partition", "Partition",
      choices = c("short", "gpu", "medium", "long",
                  "mpi", "priority", "transfer"),
      selected = init_job[1], width = "95%"
    )
  })

  output$duration <- renderUI({
    textInput(
      "duration", "Time Limit", value = init_job[2], width = "95%"
    )
  })

  output$mem <- renderUI({
    textInput(
      "mem", "Memory", value = init_job[3], width = "95%"
    )
  })

  output$n <- renderUI({
    textInput("n", "-n", value = init_job[4], width = "95%")
  })

  output$c <- renderUI({
    textInput("c", "-c", value = init_job[5], width = "95%")
  })

  output$N <- renderUI({
    textInput("N", "-N", value = init_job[6], width = "95%")
  })

  output$o <- renderUI({
    textInput("o", "-o", value = init_job[7], width = "95%")
  })

  output$gpu <- renderUI({
    textInput("gpu", "# GPU", value = init_job[8], width = "95%")
  })

  o2job <- reactive({
    c(input$partition, input$duration, input$mem,
      input$n, input$c, input$N, input$o, input$gpu)
  })

  observeEvent(o2job(), writeLines(o2job(), "~/.o2job"))

  job_options <- reactive({
    options <- c(
      paste("-p", input$partition),
      paste("-t", input$duration),
      paste0("--mem=", input$mem)
    )
    if (input$n != "") options <- c(options, paste("-n", input$n))
    if (input$c != "") options <- c(options, paste("-c", input$c))
    if (input$N != "") options <- c(options, paste("-N", input$N))
    if (input$o != "") options <- c(options, paste("-o", input$o))
    if (input$partition == "gpu") {
      options <- c(options, paste0("--gres=gpu:", input$gpu))
    }
    options <- paste(options, collapse = " ")
    return(options)
  })

  job_int <- reactive({
    req(input$partition)
    paste0("srun --pty ", job_options(), " /bin/bash")
  })

  callModule(sendTerm, "run_int", code = job_int, term_id = term_id,
             execute = code_exec)


  shinyFileChoose(input, 'file', roots =  c(home = "~"))

  script_path <- reactive({
    req(input$file)
    paths <- unlist(input$file$files$`0`)
    paths[1] <- "~"
    path <- normalizePath(paste(paths, collapse = .Platform$file.sep))
    path_local <- normalizePath(input$local)
    path <- substr(path, nchar(path_local) + 1, nchar(path))
    paste0(meta()[2], path)
  })

  job_batch <- reactive({
    req(input$partition)
    if (isTruthy(input$file)) {
      return(paste("sbatch", job_options(), script_path(),
                   "-o out.%j -e err.%j"))
    }
    return("Select a .sh Script")
  })

  observeEvent(input$check_batch, {
    rstudioapi::terminalActivate(term_id)
    rstudioapi::terminalSend(term_id, "squeue -u $USER\n")
  })


  callModule(sendTerm, "run_batch", code = job_batch, term_id = term_id,
             execute = code_exec)

  module_code <- reactive({
    paste("module", input$module)
  })

  callModule(sendTerm, "run_module", code = module_code, term_id = term_id,
             execute = code_exec)


  # sshkey-gen ================================================================
  sshkeygen <- reactive({
    req(input$o2id)
    paste0('ssh-keygen -t rsa -C ', '"', input$o2id, '"')
  })

  callModule(sendTerm, "run_sshkeygen", code = sshkeygen, term_id = term_id,
             execute = code_exec)

  output$sshkey_config <- renderText({
    paste0("Host o2 o2.hms.harvard.edu\n AddKeysToAgent yes\n HostName o2.hms.harvard.edu\n IdentityFile ~/.ssh/", input$sshkey_file)
  })

  output$sshkey_config_btn <- renderUI({
    actionButton("sshkey_config_file", label = icon("play"), width = "95%",
                 style = "height: 93px; margin-left: 2px;")
  })

  observeEvent(input$sshkey_config_file, {
    file.edit("~/.ssh/config")
  })

  sshkey_scp <- reactive({
    req(input$o2id)
    paste0('scp ~/.ssh/', input$sshkey_file, ".pub ", input$o2id, '@o2.hms.harvard.edu:')
  })

  callModule(sendTerm, "run_sshkey_scp", code = sshkey_scp, term_id = term_id,
             execute = code_exec)

  callModule(sendTerm, "run_ssh_login", code = meta_login, term_id = term_id,
             execute = code_exec)

  output$sshkey_auth <- renderUI({
    tagList(
      textInput("sshkey_auth_1", NULL, "mkdir -p ~/.ssh", width = "100%"),
      textInput("sshkey_auth_2", NULL, "touch ~/.ssh/authorized_keys", width = "100%"),
      textInput("sshkey_auth_3", NULL,
                paste0("cat ~/", input$sshkey_file, ".pub >> ~/.ssh/authorized_keys"), width = "100%"),
      textInput("sshkey_auth_4", NULL, paste0("rm ~/", input$sshkey_file, ".pub"), width = "100%")
    )
  })

  output$sshkey_auth_btn <- renderUI({
    actionButton("sshkey_auth_run", label = icon("play"), width = "95%",
                 style = "height: 180px; margin-left: 2px;")
  })

  observeEvent(input$sshkey_auth_run, {
    rstudioapi::terminalActivate(term_id)
    rstudioapi::terminalSend(term_id, paste0(input$sshkey_auth_1, "\n"))
    rstudioapi::terminalSend(term_id, paste0(input$sshkey_auth_2, "\n"))
    rstudioapi::terminalSend(term_id, paste0(input$sshkey_auth_3, "\n"))
    rstudioapi::terminalSend(term_id, paste0(input$sshkey_auth_4, "\n"))
  })
}

#' RO2 RStudio Addin
#'
#' @export
ro2_addin <- function() {
  runGadget(ro2_ui, ro2_server, viewer = paneViewer())
}
