 

get_top_pairs = function(data, top_level){
  if(top_level == "R"){
    ### get strongest target for each regulator
    df = data %>% select(target, regulator, pvalue, context) %>%
      group_by(regulator, target) %>%
      summarize(min_val = min(pvalue, na.rm = TRUE), .groups = "drop") %>%
      group_by(regulator) %>%
      slice_min(order_by = min_val, n = 1, with_ties = FALSE)  # choose one target with smallest value
    pairs = paste0(df$regulator, ":", df$target)
    return(pairs)
  }else if(top_level == "T"){
    ### get strongest regulator for each target
    df = data %>% select(target, regulator, pvalue, context) %>%
      group_by(target, regulator) %>%
      summarize(min_val = min(pvalue, na.rm = TRUE), .groups = "drop") %>%
      group_by(target) %>%
      slice_min(order_by = min_val, n = 1, with_ties = FALSE)  # choose one target with smallest value
    pairs = paste0(df$regulator, ":", df$target)
    return(pairs)
  }else{
    stop("No valid input specified for target or regulator as top level.")
  }
}


#' @export
multiple_testing_correction = function(crocotel_dir, out_dir, fdr_thresh = 0.05, method = "treeQTL", top_level = "R"){
  method_outdir = paste0(out_dir, "/", method, "_output/")
  dir.create(method_outdir, showWarnings = F)
  exp_suffix = gsub("_output", "", basename(crocotel_dir))
  if(top_level == "R"){
    output_prefix = "eRegulators"
  }else if(top_level == "T"){
    output_prefix = "eTargets"
  }else{
    stop("No valid input specified for target or regulator as top level.")
  }
  if(method == "treeQTL"){
    level1 = fdr_thresh
    level2 = fdr_thresh
    level3 = fdr_thresh
    
    eGenes = get_eGenes_multi_tissue_mod(crocotel_dir = crocotel_dir, 
                                         exp_suffix = exp_suffix,
                                         out_dir = method_outdir,
                                         top_level = top_level,
                                         level1 = level1, level2 = level2, level3 = level3)
    fwrite(eGenes, file = paste0(method_outdir, output_prefix, ".", exp_suffix, ".txt"), sep = "\t")
  }
  if(method == "mashr"){
    data = fread(crocotel_sum_stats, sep = "\t", data.table = F)

    #### pivot wider to get betas and ses in right format
    betas = data %>% mutate(targ_reg = paste0(regulator, ":", target)) %>%
      select(targ_reg, beta, context) %>% 
      pivot_wider(
        names_from = context,
        values_from = beta
      ) %>% as.data.frame()
    rownames(betas) = betas$targ_reg
    betas = betas %>% select(-targ_reg)
    betas = as.matrix(betas)
    
    ses = data %>% mutate(targ_reg = paste0(regulator, ":", target)) %>%
      select(targ_reg, se, context) %>% 
      pivot_wider(
        names_from = context,
        values_from = se
      ) %>% as.data.frame()
    rownames(ses) = ses$targ_reg
    ses = ses %>% select(-targ_reg)
    ses = as.matrix(ses)
    
    mash_data = mash_set_data(betas, ses)
    
    ### set up canonical covariance matrix
    U.c = cov_canonical(mash_data)  
    
    ### set up data driven covariance matrix
    pairs = get_top_pairs(data, top_level)
    indices = which(rownames(betas) %in% pairs)
    U.pca = cov_pca(mash_data,5,subset=indices)
    
    #### apply extreme deconvolution
    U.ed = cov_ed(mash_data, U.pca, subset=indices)
    
    #### run mash
    m = mash(mash_data, c(U.c,U.ed))
    sig_results = get_lfsr(m)
    sig_beta = get_pm(m) 
    sig_se = get_psd(m)
    ## pivot to long format
    sig_results = as.data.frame(sig_results) %>% mutate(pair = rownames(.)) %>%
      separate(pair, into = c("regulator", "target"), sep = ":") %>%
      pivot_longer(
        cols = -c(regulator, target),
        names_to = "context",
        values_to = "p.value"
      ) %>% filter(p.value <= 0.05)
    
    fwrite(sig_results[significant_rows,], file = paste0(outdir, output_prefix, ".", exp_suffix, ".txt"))
  }
}