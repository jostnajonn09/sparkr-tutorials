##################################
## Subsetting SparkR DataFrames ##
##################################

## Sarah Armstrong, Urban Institute  
## July 1, 2016  
## Last Updated: August 17, 2016


## Objective: Now that we understand what a SparkR DataFrame (DF) really is (remember, it's not actually data!) and can write expressions using essential DataFrame operations, such as `agg`, we are ready to start subsetting DFs using more advanced transformation operations. This tutorial discusses various ways of subsetting DFs, as well as how to work with a randomly sampled subset as a local data.frame in RStudio:

## * Subset a DF by row
## * Subset a DF by a list of columns
## * Subset a DF by column expressions
## * Drop a column from a DF
## * Subset a DF by taking a random sample
## * Collect a random sample as a local R data.frame
## * Export a DF sample as a single .csv file to S3

## SparkR/R Operations Discussed: `filter`, `where`, `select`, `sample`, `collect`, `write.table`


## Initiate SparkR session:

if (nchar(Sys.getenv("SPARK_HOME")) < 1) {
  Sys.setenv(SPARK_HOME = "/home/spark")
}
library(SparkR, lib.loc = c(file.path(Sys.getenv("SPARK_HOME"), "R", "lib")))
sparkR.session()

## Read in example HFPC data from AWS S3 as a DataFrame (DF):

df <- read.df("s3://sparkr-tutorials/hfpc_ex", header = "false", inferSchema = "true")
cache(df)


## Let's check the dimensions our DF `df` and its column names so that we can compare the dimension sizes of `df` with those of the subsets that we will  define throughout this tutorial:
nrow(df)
ncol(df)
columns(df)

##################################
## (1) Subset DataFrame by row: ##
##################################

## The SparkR operation `filter` allows us to subset the rows of a DF according to specified conditions. Before we begin working with `filter` to see how it works, let's print the schema of `df` since the types of subsetting conditions we are able to specify depend on the datatype of each column in the DF: 

printSchema(df)

## We can subset `df` into a new DF, `f1`, that includes only those loans for which JPMorgan Chase is the servicer with the expression:

f1 <- filter(df, df$servicer_name == "JP MORGAN CHASE BANK, NA" | df$servicer_name == "JPMORGAN CHASE BANK, NA" |
               df$servicer_name == "JPMORGAN CHASE BANK, NATIONAL ASSOCIATION")
nrow(f1)

## Notice that the `filter` considers normal logical syntax (e.g. logical conditions and operations), making working with the operation very straightforward. We can specify `filter` with SQL statement strings. For example, here we have the preceding example written in SQL statement format:

filter(df, "servicer_name = 'JP MORGAN CHASE BANK, NA' or servicer_name = 'JPMORGAN CHASE BANK, NA' or
       servicer_name = 'JPMORGAN CHASE BANK, NATIONAL ASSOCIATION'")

## Or, alternatively, in a syntax similar to how we subset data.frames by row in base R:

df[df$servicer_name == "JP MORGAN CHASE BANK, NA" | df$servicer_name == "JPMORGAN CHASE BANK, NA" | 
     df$servicer_name == "JPMORGAN CHASE BANK, NATIONAL ASSOCIATION",]

## Another example of using logical syntax with `filter` is that we can subset `df` such that the new DF only includes those loans for which the servicer name is known, i.e. the column `"servicer_name"` is not equa to an empty string or listed as `"OTHER"`:

f2 <- filter(df, df$servicer_name != "OTHER" & df$servicer_name != "")
nrow(f2)

## Or, if we wanted to only consider observations with a `"loan_age"` value of greater than 60 months (five years), we would evaluate:

f3 <- filter(df, df$loan_age > 60)
nrow(f3)

## An alias for `filter` is `where`, which reads much more intuitively, particularly when `where` is embedded in a complex statement. For example, the following expression can be read as "__aggregate__ the mean loan age and count values __by__ `"servicer_name"` in `df` __where__ loan age is less than 60 months":

f4 <- agg(groupBy(where(df, df$loan_age < 60), where(df, df$loan_age < 60)$servicer_name), 
          loan_age_avg = avg(where(df, df$loan_age < 60)$loan_age), 
          count = n(where(df, df$loan_age < 60)$loan_age))
head(f4)

#####################################
## (2) Subset DataFrame by column: ##
#####################################

## The operation `select` allows us to subset a DF by a specified list of columns. In the expression below, for example, we create a subsetted DF that includes only the number of calendar months remaining until the borrower is expected to pay the mortgage loan in full (remaining maturity) and adjusted remaining maturity:

s1 <- select(df, "mths_remng", "aj_mths_remng")
ncol(s1)

## We can also reference the column names through the DF name, i.e. `select(df, df$mths_remng, df$aj_mths_remng)`. Or, we can save a list of columns as a combination of strings. If we wanted to make a list of all columns that relate to remaining maturity, we could evaluate the expression `remng_mat <- c("mths_remng", "aj_mths_remng")` and then easily reference our list of columns later on with `select(df, remng_mat)`.

## Besides subsetting by a list of columns, we can also subset `df` while introducing a new column using a column expression, as we do in the example below. The DF `s2` includes the columns `"mths_remng"` and `"aj_mths_remng"` as in `s1`, but now with a column that lists the absolute value of the difference between the unadjusted and adjusted remaining maturity:

s2 <- select(df, df$mths_remng, df$aj_mths_remng, abs(df$aj_mths_remng - df$mths_remng))
ncol(s2)
head(s2)

## Note that, just as we can subset by row with syntax similar to that in base R, we can similarly acheive subsetting by column. The following expressions are equivalent:

select(df, df$period)
df[,"period"]
df[,2]

## To simultaneously subset by column and row specifications, you can simply embed a `where` expression in a `select` operation (or vice versa). The following expression creates a DF that lists loan age values only for observations in which servicer name is unknown:

s3 <- select(where(df, df$servicer_name == "" | df$servicer_name == "OTHER"), "loan_age")
head(s3)

## Note that we could have also written the above expression as:

df[df$servicer_name == "" | df$servicer_name == "OTHER", "loan_age"]

###################################
## (2i) Drop a column from a DF: ##
###################################

## We can drop a column from a DF very simply by assigning `NULL` to a DF column. Below, we drop `"aj_mths_remng"` from `s1`:

head(s1)
s1$aj_mths_remng <- NULL
head(s1)

#################################################
## (3) Subset a DF by taking a random sample: ###
#################################################

## Perhaps the most useful subsetting operation is `sample`, which returns a randomly sampled subset of a DF. With `subset`, we can specify whether we want to sample with or without replace, the approximate size of the sample that we want the new DF to call and whether or not we want to define a random seed. If our initial DF is so massive that performing analysis on the entire dataset requires a more expensive cluster, we can: sample the massive dataset, interactively develop our analysis in SparkR using our sample and then evaluate the resulting program using our initial DF, which calls the entire massive dataset, only as is required. This strategy will help us to minimize wasting resources.

## Below, we take a random sample of `df` without replacement that is, in size, approximately equal to 1% of `df`. Notice that we must define a random seed in order to be able to reproduce our random sample.

df_samp1 <- sample(df, withReplacement = FALSE, fraction = 0.01)  # Without set seed
df_samp2 <- sample(df, withReplacement = FALSE, fraction = 0.01)
count(df_samp1)
count(df_samp2)
# The row counts are different and, obviously, the DFs are not equivalent

df_samp3 <- sample(df, withReplacement = FALSE, fraction = 0.01, seed = 0)  # With set seed
df_samp4 <- sample(df, withReplacement = FALSE, fraction = 0.01, seed = 0)
count(df_samp3)
count(df_samp4)
# The row counts are equal and the DFs are equivalent

##########################################################
## (3i) Collect a random sample as a local data.frame: ###
##########################################################

## An additional use of `sample` is to collect a random sample of a massive dataset as a local data.frame in R. This would allow us to work with a sample dataset in a traditional analysis environment that is likely more representative of the population since we are sampling from a larger set of observations than we are normally doing so. This can be achieved by simply using `collect` to create a local data.frame:

typeof(df_samp4)  # DFs are of class S4
dat <- collect(df_samp4)
typeof(dat)

## Note that this data.frame is _not_ local to _your_ personal computer, but rather it was gathered locally to a single node in our AWS cluster.

#########################################################
## (3ii) Export DF sample as a single .csv file to S3: ##
#########################################################

## If we want to export the sampled DF from RStudio as a single .csv file that we can work with in any environment, we must first coalesce the rows of `df_samp4` to a single node in our cluster using the `repartition` operation. Then, we can use the `write.df` operation as we did in the [SparkR Basics I](https://github.com/UrbanInstitute/sparkr-tutorials/blob/master/sparkr-basics-1.md) tutorial:

df_samp4_1 <- repartition(df_samp4, numPartitions = 1)
write.df(df_samp4_1, path = "s3://sparkr-tutorials/hfpc_samp.csv", source = "csv", 
         mode = "overwrite")

## __Warning__: We cannot collect a DF as a data.frame, nor can we repartition it to a single node, unless the DF is sufficiently small in size since it must fit onto a _single_ node!