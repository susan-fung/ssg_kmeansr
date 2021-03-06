# ssgkmeansr
library(magrittr)
library(dplyr)
library(ggplot2)

#' Convert raw input data to data frame
#'
#' @param raw Raw input
#' @param stage `fit` or `predict`
#'
#' @return Cleaned data in data frame format
#' @export
#'
input_preprocessing <- function(raw, stage) {
  tryCatch({
    data <- as.data.frame(raw)
  }, error = function(e) {
    stop('Failed to convert data to data frame.')
  })
  
  ncols <- 0
  if (stage == 'fit') {
    ncols <- 2
  } else {
    ncols <- 3
  }
  if (nrow(data) <= 0) {
    stop('Input data cannot be empty.')
  }
  if (ncol(data) != ncols) {
    stop(paste('Input data must have', ncols, 'columns.'))
  }
  if (!is.numeric(unlist(data[,1]))) {
    stop('Input data must be numeric')
  }
  if (!is.numeric(unlist(data[,2]))) {
    stop('Input data must be numeric')
  }
  
  # change column names
  tryCatch({
    if (stage == 'fit') {
      colnames(data) <- c('x1', 'x2')
    } else if (stage == 'predict') {
      colnames(data) <- c('x1', 'x2', 'cluster')
    }
  }, error = function(e) {
    stop('Failed to assign column names.')  
  })
  
  # change cluster column to factor type
  if (stage != 'fit' & ncol(data) == 3) {
    tryCatch({
      data <- data %>% mutate(
        cluster = as.factor(cluster)
      )
    }, error = function(e) {
      stop('Failed to convert cluster label to factor.')
    })
  }
  
  return(data)
}


#' Euclidean distance between any two points
#'
#' @param p1 First point
#' @param p2 Second point
#'
#' @return number
#' @export
euc_dist <- function(p1, p2) {
  tryCatch({
    sqrt(sum((p1 - p2)^2))
  }, error = function(e) {
    stop('Error in calculating the Euclidean distance.')
  })
}


#' Find the centroid of a cluster
#'
#' @param dat Data points
#'
#' @return vector of centroid coordinates
#' @export
find_centroid <- function(dat) {
  tryCatch({
    mat <- as.matrix(dat)
    x1 <- mean(mat[,1])
    x2 <- mean(mat[,2])
    c(x1, x2)
  }, error = function(e) {
    stop('Failed to get the centroid from the cluster.')
  })
}

#' Check if converged
#'
#' @param c0 Previous centroid
#' @param c1 New centroid
#' @param eps Tolerance
#'
#' @return bool
#' @export
should_stop <- function(c0, c1, eps) {
  # c0 as the matrix of prev centroids
  # c1 as the matrix of the new centroids
  c_diff <- abs(c0 - c1)
  idx_diff <- c()
  idx_diff <- which(c_diff > eps)
  if (length(idx_diff) == 0) {
    # stop if converged
    return(TRUE)
  } else {
    return(FALSE)
  }
}

#' Find the initial centroids using the kmeans++ approach
#' 
#' @param data The input data
#' @param K The number of clusters
#' @return The indices of the centroids in the input data
#' @note This function is not optimized for performance or efficiency
kmpp <- function(data, K) {
  num_obs <- nrow(data)
  
  if (num_obs <= 0) stop('Invalid input: empty data.')
  
  # sample the first centroid and add it to vector
  idx0 <- sample(1:num_obs, 1)
  centroids <- c()
  centroids <- c(centroids, idx0)  # as indices
  
  df <- data.frame(
    x1 = unlist(data[,1]),
    x2 = unlist(data[,2])
  )
  
  # dist from a point to its nearest centroid
  get_dist <- Vectorize(function(x1, x2) {
    tryCatch({
      d <- c()  # distance vector
      # calc distance to all centroids in the vector
      for (cent in centroids) {
        tmp <- euc_dist(c(x1, x2), data[cent,])
        d <- c(d, tmp)
      }
      min(d)
    }, error = function(e) {
      stop('Failed to calculate the distance to centroid.')
    })
  })
  
  # find which cluster a point belongs to
  get_clust <- Vectorize(function(x1, x2) {
    tryCatch({
      d <- c()
      for (cent in centroids) {
        tmp <- euc_dist(c(x1, x2), data[cent,])
        d <- c(d, tmp)
      }
      # use index as the cluster label
      which.min(d)
    }, error = function(e) {
      stop('Failed to assign cluster label.')
    })
  })
  
  for (i in 1:K) {
    # the df gets updated every time a new centroid is calculated
    df <- df %>%
      mutate(
        D = get_dist(x1, x2),  # D as the min distance to the nearest centroid
        clust = get_clust(x1, x2)  # cluster of each data point
      ) %>%
      group_by(clust) %>%
      # not sure if I understand it correctly, it seems probability is based on
      # the distance within each cluster. So here I group the data by cluster first.
      mutate(
        prob = (D - min(D)) / (max(D) - min(D))
      ) %>%
      ungroup(clust)
    
    if (i < K) {
      # Get a new centroid based on probabilities and add it to the vector.
      # The functions, `get_dist` and `get_clust` will use the updated vector
      c_new <- sample(1:dim(data)[1], 1, prob=df$prob)
      centroids <- c(centroids, c_new)
    }
  }
  # print(centroids)
  # return(df)
  centroids
}

#' initalize centroids using random or kmpp
#'
#' @param method Initialization method
#' @param N Number of data points
#' @param K Number of clusters
#' @param data Data points
#'
#' @return integer Index of data points
#' @export
init_cent <- function(method, N, K, data) {
  m <- tolower(method)
  if (m %in% c('random', 'rand')) {
    centroids <- sample(1:N, K)
    return(centroids)
  } else if (m %in% c('kmpp', 'km++', 'kp')) {
    centroids <- kmpp(data, K)
    return(centroids)
  } else {
    warning('Invalid initialization method. Using default: random.')
    centroids <- sample(1:N, K)
    return(centroids)
  }
}

#' Calculate the total within cluster sum of squared distance
#'
#' @param data_cluster Data points in cluster
#' @param centroid Centroid of the cluster
#'
#' @return number
#' @export
calcWitinSS <- function(data_cluster, centroid) {
  wss <- 0
  for (j in 1:nrow(data_cluster)) {
    wss <- wss + euc_dist(data_cluster[j,], centroid)
  }
  if (wss < 0) {
    warning('The total within cluster sum of squared error is less than 0.')
  }
  wss
}


#' Compute k-means clustering
#' 
#' Build clusters and save cluster attributes with random selection or k-means ++ centroid initialization
#'
#' @param data A data frame with attributes as columns and data points as rows
#' @param K Number of clusters
#' @param method Centroid initialization method. `random` or `kmpp`
#'
#' @return List containing: 1. data frame of the attributes and clustering for each data point; 2.total within cluster sum of square; 3. data frame of k centroids
#' @export
fit <- function(data, K, method='random') {
  data <- input_preprocessing(data, 'fit')
  nobs <- nrow(data)  # number of observations
  
  
  if (K < 1 | K > nrow(data)) {
    stop('Invalid number of clusters. K must be larger than 1 and smaller than the number of rows in the data.')
  }
  
  # initialize centroids as indices of data
  cent_init <- init_cent(method, nobs, K, data)
  centroids <- data[cent_init,]  # actual coords
  # distance matrix n by K: distance from each obs to each centroid
  dist_mat <- matrix(
    rep(0, nobs * K),
    nrow = nobs,
    ncol = K
  )
  # cluster labels
  labels <- rep(0, nobs)
  eps <- 0
  n_iter <- 0
  
  stop <- FALSE
  while (!stop) {
    # calc distance from each obs to each centroid
    for (row in 1:nobs) {
      for (idx_cent in 1:K) {
        dist_mat[row, idx_cent] <- euc_dist(data[row,], centroids[idx_cent,])
      }
      idx_min <- which.min(dist_mat[row,])
      # assign label based on the min distance
      labels[row] <- idx_min
    }
    
    # group data based on labels
    data_in_clust <- list()
    # new centroids based on labels
    centroids_new <- matrix(  # init
      rep(0, K*2),
      nrow = K,
      ncol = 2
    )
    for (k in 1:K) {
      indices <- which(labels == k)
      data_in_clust[[k]] <- data[indices,]
      centroids_new[k,] <- find_centroid(data_in_clust[[k]])
    }
    if (should_stop(centroids, centroids_new, eps)) {
      stop <- TRUE
    }
    # update centroids
    centroids <- centroids_new
    n_iter <- n_iter + 1
  }
  print(paste("kmeans converged in", n_iter, "runs."))
  
  data_with_labels <- data.frame(x1 = data$x1,
                                 x2 = data$x2,
                                 cluster = labels)
  withinSS <- 0
  for (k in 1:K) {
    withinSS <- withinSS + calcWitinSS(data_in_clust[[k]], centroids[k,])
  }
  
  return(list(
    data = data_with_labels,
    withinSS = withinSS,
    centroids = as.data.frame(centroids,row.names=NULL)
  ))
}


#' Predict k-means clustering; provide labels for all observations
#'
#' @param data A to-be-predicted new dataframe with attributes as columns and data points as rows. Data without cluster labels
#' @param centroids model from fit function; a data frame of centroids

#' @return Dataframe containing new data and clustering label for each data point
#' @export
predict <- function(data, centroids) {
  
  data <- input_preprocessing(data, 'fit')
  
  nobs <- nrow(data)  # num of observations
  K <- nrow(centroids)  # number of clusters
  
  # init for calculation
  dist_mat <- matrix(
    rep(0, nobs * K),
    nrow = nobs,
    ncol = K
  )
  labels <- rep(0, nobs)
  
  for (row in 1:nobs) {
    for (idx_cent in 1:K) {
      dist_mat[row, idx_cent] <- euc_dist(data[row,], centroids[idx_cent,])
    }
    idx_min <- which.min(dist_mat[row,])
    # assign label based on the min distance
    labels[row] <- idx_min
  }
  
  res <- data %>%
    mutate(cluster = labels)
  res
}


#' Visualize kmeans results
#'
#' @param dat dataframe. Data with cluster labels
#'
#' @return ggplot object
#' @export
kmplot <- function(dat) {
  tryCatch({
    data_clean<-input_preprocessing(dat,"plot")
    
    data <- data_clean %>%
      mutate(cluster = as.factor(cluster))
    
    fig <- data %>%
      ggplot(aes(x1, x2)) +
        geom_point(aes(color = cluster)) +
        scale_color_discrete('cluster') +
        scale_x_continuous('x1') +
        scale_y_continuous('x2') +
        theme_bw()
    
    return(fig)
  }, error = function(e) {
    stop(e)
  })
}
