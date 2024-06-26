library(tidyverse)
library(ranger)
library(mRMRe)
library(randomForest)
library(psdR)
library(umap)

meta_data <- read.csv("data/meta_data.csv")

summary(factor(meta_data$subcohort))
# data_dummy <- data.frame("sample" = paste0("s", seq(1,100)),
#                          "Label" = c(rep("yes", 40), rep("no", 60)),
#                          "f1" = c(runif(40, min = 1, max = 10),
#                                   runif(60, min = 30, max = 50)),
#                          "f2" = c(runif(40, min = 100, max = 101),
#                                   runif(60, min = 102, max = 103)),
#                          "f3" = c(runif(40, min = 20, max = 24),
#                                   runif(60, min = 23, max = 25)),
#                          "f4" = c(runif(100, min = 20, max = 80))
#                          )
# data <- data_dummy %>%
#   select(-c(Label)) %>%
#   column_to_rownames("sample")
# output_labels <- data_dummy[, 1:2]


data <- read.csv("data/formatted_data.csv")

# data <- read.csv("data/all_level_formatted_data.csv")
colnames(data)[1] <- "sample"
sum(is.na(data))

# output_labels <- meta_data %>%
#   filter(!is.na(RECIST) & RECIST != "SD") %>%
#   select(c(sample, ICIresponder)) 

output_labels <- meta_data %>%
  # filter(!is.na(RECIST) & RECIST != "SD") %>%
  filter(subcohort %in% c("PRIMM-NL", "PRIMM-UK")) %>%
  select(c(sample, ICIresponder)) 

output_labels <- output_labels %>%
  dplyr::rename(c("Label" = "ICIresponder"))


combined_data <- output_labels %>%
  inner_join(data)

missing1 <- output_labels %>%
  anti_join(data)
missing2 <- data %>%
  anti_join(output_labels)


data <- combined_data %>%
  select(-c(Label)) %>%
  column_to_rownames("sample")

assertthat::are_equal(rownames(data), output_labels$sample)



#############################

random_seed = 1000
set.seed(random_seed)
train_index <- caret::createDataPartition(output_labels$Label, p = .8, 
                                          list = FALSE, 
                                          times = 1)

data.train <- data[train_index, ]
label.train <- output_labels[train_index, ]

data.test <- data[-train_index, ]
label.test <- output_labels[-train_index, ]




#filter and transform

#filter features with overall abundance != 0

filtered_features <- colSums(data.train) != 0
sum(filtered_features)
data.train <- data.train[, filtered_features]
data.test <- data.test[, filtered_features]

min(data.train)
max(data.train)
sum(data.train == 0)
dim(data.train)[1] * dim(data.train)[2]

min(data.train[data.train != 0])
#4e-05

data.train <- data.train + 10^-5
data.test <- data.test + 10^-5

min(data.train)

data.train <- log(data.train)
data.test <- log(data.test)

# data.train <- data.frame(psd(data.train))
# data.test <- data.frame(psd(data.test))

#filter and transform end

normparam <- caret::preProcess(data.train) 
data.train <- predict(normparam, data.train)
data.test <- predict(normparam, data.test) #normalizing test data using params from train data 

colSums(data.train)

# data.train <- data.frame(psd(data.train))
# data.test <- data.frame(psd(data.test))

### dim red plots

set.seed(1000)
result <- Rtsne::Rtsne(data.train, perplexity = 10)
dim_red_df <- data.frame(x = result$Y[,1], y = result$Y[,2], 
                         Colour = label.train$Label)    
xlab <- "tSNE 1"
ylab <- "tSNE 2"

ggplot2::ggplot(dim_red_df) +
  ggplot2::geom_point(ggplot2::aes(x = x, y = y, colour = Colour)) +
  ggplot2::labs(title = "tSNE") +
  ggplot2::xlab(xlab) +
  ggplot2::ylab(ylab)

result <- umap(data.train)
dim_red_df <- data.frame(x = result$layout[,1], y = result$layout[,2], 
                         Colour = label.train$Label)  
xlab <- "UMAP 1"
ylab <- "UMAP 2"

ggplot2::ggplot(dim_red_df) +
  ggplot2::geom_point(ggplot2::aes(x = x, y = y, colour = Colour)) +
  ggplot2::labs(title = "UMAP") +
  ggplot2::xlab(xlab) +
  ggplot2::ylab(ylab)

### dim red plots end

assertthat::are_equal(rownames(data.train), label.train$sample)
assertthat::are_equal(rownames(data.test), label.test$sample)



#ranger
set.seed(random_seed)

ranger_model <- ranger::ranger(x = data.train, y = factor(label.train$Label), 
                               importance = "impurity_corrected")

summary(ranger_model$variable.importance)

hist(ranger_model$variable.importance)

features <- which(ranger_model$variable.importance >= 0)

# features <- which(ranger_model$variable.importance >= quantile(ranger_model$variable.importance)[3])

data.train <- data.train[, features, drop = FALSE]
data.test <- data.test[, features, drop = FALSE]


#mrmr

# classes = c("yes", "no")
# 
# mrmr.data.train <- mRMRe::mRMR.data(data = data.frame(
#   target = factor(label.train$Label, levels = classes, ordered = TRUE),
#   data.train))
# filter <- mRMRe::mRMR.classic(data = mrmr.data.train, target_indices = c(1), feature_count = 400)
# 
# features <- mRMRe::solutions(filter)[[1]] - 1
# 
# data.train <- data.train[, features, drop = FALSE]
# data.test <- data.test[, features, drop = FALSE]

#mrmr end



assertthat::are_equal(rownames(data.train), label.train$sample)
assertthat::are_equal(rownames(data.test), label.test$sample)


#classification

classes = c("yes", "no")

logistic_regression(data.train, label.train, 
                    data.test, label.test,
                    classes, regularize = "l2")
logistic_regression(data.train, label.train, 
                    data.test, label.test,
                    classes, regularize = "l1")



svm_model(data.train, label.train, data.test, label.test, 
          classes, kernel = "sigmoid")
svm_model(data.train, label.train, data.test, label.test, 
          classes, kernel = "radial")

rf_model(data.train, label.train, data.test, label.test, 
          classes)


#ranger 3rd quantile features 

  #with l2 logreg
# [1] 0.5
# [1] 0.7651515
# [1] 0.5625
# [1] 0.56250000 0.54761905 0.07142857 0.94444444

  #with svm sigmoid kernel
# [1] 0.6562500 0.5873016 0.4285714 0.8333333

  #with svm radial kernel
# [1] 0.6875000 0.5873016 0.5000000 0.8333333


# on PRIMM-NL data
# [1] 0.5
# [1] 0.7111111
# [1] 0.6
# [1] 0.6000000 0.1666667 0.0000000 1.0000000

  #without SD
# [1] 0.5
# [1] 1
# [1] 0.625
# [1] 0.625 0.375 0.500 0.750



# on PRIMM-UK data
# > logistic_regression(data.train, label.train, 
#                       +                     data.test, label.test,
#                       +                     classes, regularize = "l2")
# [1] 0.5
# [1] 0.6136364
# [1] 0.6
# [1] 0.6000000 0.7916667 0.0000000 1.0000000
# > logistic_regression(data.train, label.train, 
#                       +                     data.test, label.test,
#                       +                     classes, regularize = "l1")
# [1] 0.5
# [1] 0.8863636
# [1] 0.6
# [1] 0.600 0.875 0.000 1.000
# > svm_model(data.train, label.train, data.test, label.test, 
#             +           classes, kernel = "sigmoid")
# [1] 0.7000000 0.7500000 0.5000000 0.8333333
# > svm_model(data.train, label.train, data.test, label.test, 
#             +           classes, kernel = "radial")
# [1] 0.70 0.75 0.25 1.00
# > rf_model(data.train, label.train, data.test, label.test, 
#            +           classes)
# [1] 0.70 1.00 0.25 1.00


# on PRIMM-UK data without SD
# > logistic_regression(data.train, label.train, 
#                       +                     data.test, label.test,
#                       +                     classes, regularize = "l2")
# [1] 0.5
# [1] 0.8333333
# [1] 0.7142857
# [1] 0.7142857 0.6666667 0.3333333 1.0000000