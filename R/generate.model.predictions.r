#' Generate model predictions function
#'
#' This function bins model predictions and converts them from character labels to numeric labels.
#' @param study_data The study data frame. No default
#' @param n_cores Number of cores to be used in parallel gridsearch. Passed to bin.models (which, in turn, passes to SupaLarna::gridsearch.breaks). As integer. Defaults to 2 (in gridsearch.breaks)
#' @param return_cps Logical. Function returns model cut_points if TRUE. Passed to bin.models. Defaults to TRUE.
#' @param log Logical. If TRUE progress is logged in logfile. Defaults to FALSE.
#' @param boot Logical. Affects only what is printed to logfile. If TRUE prepped_sample is assumed to be a bootstrap sample. Defaults to FALSE.
#' @param write_to_disk Logical. If TRUE the prediction data is saved as RDS to disk. Defaults to FALSE.
#' @param clean_start Logical. If TRUE the predictions directory and all files in it are removed before saving new stuff there. Defaults to FALSE.
#' @param gridsearch_parallel Logical. Passed to bin.models (which, in turn, passes to SupaLarnas gridsearch.breaks). If TRUE the gridsearch is performed in parallel. Defaults to FALSE.
#' @param is_sample Logical. Passed to bin.models. If TRUE, only a tenth of possible cut points is searched. Defaults to TRUE.
#' @param clean_start Logical. If TRUE the predictions directory and all files in it are removed before saving new stuff there. Defaults to FALSE.
#' @export
generate.model.predictions <- function(
                                       study_data,
                                       n_cores,
                                       return_cps = FALSE,
                                       log = FALSE,
                                       boot = FALSE,
                                       write_to_disk = FALSE,
                                       clean_start = FALSE,
                                       gridsearch_parallel = TRUE,
                                       is_sample = TRUE
                                       )
{
    ## Extract outcome for gridsearch
    dataset_outcomes <- list(y_train =  study_data$train$s30d,
                             y_test =  study_data$test$s30d)
    ## Extract tc from test dataset and bind test outcome;
    ## may be extended for test-train model comparison
    tc_and_outcome <- list(tc = as.numeric(study_data$test$tc),
                           s30d = study_data$test$s30d)
    ## Define model_names
    model_names <- c("RTS", "GAP", "KTS", "gerdin")
    ## Define suffixes for later predictions
    suffixes <- setNames(nm = c("_CUT", "_CON"))
    ## Define model settings for gridsearch
    model_settings <- list(model_steps = setNames(as.list(c(0.5, 1, 1, 0.01)), # Steps for grid
                                                  nm = model_names),
                           model_optimise = setNames(as.list(c(FALSE, FALSE, FALSE, TRUE)),
                                                     nm =  model_names))
    ## Define dir_name for write_to_disk
    dir_name <- "predictions"
    if (clean_start) {
        if (dir.exists(dir_name)) unlink(dir_name, recursive = TRUE)
        if (file.exists("logfile")) file.remove("logfile")
        if (log) write("Nothing yet...", "logfile")
    }    
    ## Generate predictions with models
    pred_data <- unlist(lapply(model_names, function(model_name, suffixes,
                                                     model_settings){
        ## Get function from string
        model_func <- get(paste0("model.", model_name))
        ## Make predictions on test and train set
        predictions <- lapply(setNames(nm = names(study_data)), function(train_or_test)
            model_func(study_data[[train_or_test]]))
        ## Define steps
        step <- model_settings$model_steps[[model_name]]
        ## Define grid with the predictions on the train set; for gridsearch
        grid <-  seq(min(predictions$train), max(predictions$test),
                     by = step)
        ## Get the optimise setting corresponding to the model
        optimise <- model_settings$model_optimise[[model_name]]
        ## Gridsearch on train set, and bin predictions on test set
        binned_preds <- bin.models(predictions = predictions,
                                   outcomes = dataset_outcomes$y_train,
                                   grid = grid,
                                   n_cores = n_cores,
                                   return_cps = return_cps,
                                   gridsearch_parallel = gridsearch_parallel,
                                   is_sample = is_sample,
                                   maximise = optimise)
        ## Convert to numeric predictions
        binned_predictions <- lapply(binned_preds, function(preds){
            levels(preds) <- as.character(1:4)
            preds <- as.numeric(preds)
        })
        ## List prediction data, i.e. the continous predictions and binned predictions on test set
        pred_data <- setNames(list(binned_predictions$test,
                                   predictions$test),
                              nm = sapply(suffixes, function(suffix)
                                  paste0(model_name, suffix)))
        return (pred_data)}, suffixes = suffixes, model_settings = model_settings),
        recursive = FALSE)
    ## Bind outcome and tc to prediction data
    pred_data <- c(pred_data, tc_and_outcome)
    ## Define timestamp
    timestamp <- Sys.time()
    file_name <- ""
    ## Write each prediction to disk
    if (write_to_disk) {
        if (!dir.exists(dir_name)) dir.create(dir_name)
        filenum <- as.character(round(as.numeric(timestamp)*1000))
        file_name_ext <- "main"
        if (boot) file_name_ext <- "boot"
        file_name <- paste0(dir_name, "/model_predictions_", file_name_ext, "_", filenum, ".rds")
        saveRDS(pred_data, file_name)
        file_name <- paste0("saved in ", file_name, " ")
    }
    ## Log
    if (log) {
        analysis_name <- "Main"
        if (boot) analysis_name <- "Bootstrap"
        logline <- paste0(analysis_name, " analysis ", file_name, "completed on ", timestamp)
        append <- ifelse(clean_start, FALSE, TRUE)
        write(logline, "logfile", append = append)
    }
    ## Return pred_data and cut_points
    return (pred_data)
}

