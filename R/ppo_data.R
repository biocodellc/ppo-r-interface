#' @title Retrieve data from PPO Data portal
#'
#' @description
#' The Global Plant Phenology Data Portal (PPO data portal) is an aggregation of phenology
#' data from several different data sources.  Currently it contains USA-NPN,
#' NEON, and PEP725 data sources.  The PPO data portal harvests data using
#' the ppo-data-pipeline, with code available at \url{https://github.com/biocodellc/ppo-data-pipeline/}.
#' You may also view PPO data portal products online at \url{http://plantphenology.org/}.
#'
#' @param genus a plant genus name
#' @param specificEpithet a plant specific epithet
#' @param termID a plant stage from the plant phenology ontology, e.g. obo:PPO_0002324.  Use the ppo_terms function in this package to get the relevant IDs for present and absent stages
#' @param fromYear query for years starting from this year
#' @param toYear query for years ending at this year
#' @param fromDay query for days starting from this day
#' @param toDay query for days ending at this day
#' @param bbox A lat long bounding box. Format is \code{lat,long,lat,long}. Use this website: http://boundingbox.klokantech.com/ to quickly grab a bbox (set format on bottom left to csv and be sure to switch the order from long, lat, long, lat to lat, long, lat, long)
#' Just set the format on the bottom left to CSV.
#' @param limit Limit the resultset to an integer value. Useful for testing.
#' @export
#' @keywords data download
#' @importFrom rjson fromJSON
#' @importFrom plyr rbind.fill
#' @importFrom utils read.csv
#' @import httr
#' @return data.frame
#' @examples
#' df <- ppo_data(genus = "Quercus", fromYear = 1979, toYear = 2004)
#' df <- ppo_data(bbox='44,-124,46,-122', fromDay = 1, toDay = 60)
#' df <- ppo_data(fromDay=150, limit = 10)

ppo_data <- function(genus = NULL, specificEpithet = NULL, termID = NULL, fromYear = NULL, toYear = NULL, fromDay = NULL, toDay = NULL, bbox = NULL, limit = NULL ) {

  # source Parameter refers to the data source we want to query for
  # here we limit to only USA-NPN and NEON
  sourceParameter = "source:USA-NPN,NEON"
  # source Argument refers to the fields we want returned
  sourceArgument = "source=latitude,longitude,year,dayOfYear,plantStructurePresenceTypes"

  # Check for minimum arguments to run a query
  main_args <- z_compact(as.list(c(genus, specificEpithet, termID, bbox)))
  date_args <- z_compact(as.list(c(fromYear, toYear, fromDay, toDay)))
  arg_lengths <- c(length(main_args), length(date_args))

  if (any(arg_lengths) < 1) {
    stop("Please specify at least 1 query argument")
  }

  # set the base_url for making calls
  base_url <- "http://api.plantphenology.org/v1/download/";
  userParams <- z_compact(as.list(c(genus = genus, specificEpithet = specificEpithet, termID = termID, bbox = bbox, fromYear = fromYear, toYear = toYear, fromDay = fromDay, toDay = toDay)))

  # construct the value following the "q" key
  qArgument <- "q="
  counter = 0;   # counter to tell us if we're after 1st record
  # loop through all user parameters
  for(key in names(userParams)){
    value<-userParams[key]
    # For multiple arguments, insert AND separator.  Here, we insert html encoding + for spaces
    if (counter > 0) {
      qArgument <- paste(qArgument,"+AND+", sep = "")
    }

    if (key == "fromYear")
      qArgument <- paste(qArgument,'%2B','year:>=',value, sep = "")
    else if (key == "fromDay")
      qArgument <- paste(qArgument,'%2B','dayOfYear:>=',value, sep = "")
    else if (key == "toYear")
      qArgument <- paste(qArgument,'%2B','year:<=',value, sep = "")
    else if (key == "toDay")
      qArgument <- paste(qArgument,'%2B','dayOfYear:<=',value, sep = "")
    else if (key == "termID")
      qArgument <- paste(qArgument,'%2B','plantStructurePresenceTypes',':"',value,'"', sep = "")
    else if (key == "bbox") {
      lat1 = as.numeric(unlist(strsplit(bbox, ","))[1])
      lat2 = as.numeric(unlist(strsplit(bbox, ","))[3])
      lng1 = as.numeric(unlist(strsplit(bbox, ","))[2])
      lng2 = as.numeric(unlist(strsplit(bbox, ","))[4])
      if (lat1 > lat2) {
        minLat = lat2
        maxLat = lat1
      } else {
        minLat = lat1
        maxLat = lat2
      }
      if (lng1 > lng2) {
        minLng = lng2
        maxLng = lng1
      } else {
        minLng = lng1
        maxLng = lng2
      }
      qArgument <- paste(qArgument,'%2B','latitude',':>=',minLat, sep = "")
      qArgument <- paste(qArgument,'+AND+%2B','latitude',':<=',maxLat, sep = "")
      qArgument <- paste(qArgument,'+AND+%2B','longitude',':>=',minLng, sep = "")
      qArgument <- paste(qArgument,'+AND+%2B','longitude',':<=',maxLng, sep = "")
    } else {
      # Begin arguments using +key:value and html encode the + sign with %2B
      qArgument <- paste(qArgument,'%2B',key,':',value, sep = "")
    }
    counter = counter  + 1
  }

  # add the source argument
  qArgument <- paste(qArgument,'+AND+',sourceParameter, sep="")

  # construct the queryURL
  queryUrl <- paste(base_url,'?',qArgument,'&',sourceArgument, sep="")

  # add the limit
  if (!is.null(limit)) {
    queryUrl <- paste(queryUrl,'&limit=',limit, sep="")
  }
  # print out parameters
  print (paste('sending request to',queryUrl))
  # send GET request to URL we constructed
  results <- httr::GET(queryUrl)
  # PPO server returns a 204 status code when no results have been found
  if (results$status_code == 204) {
    print ("no results found!");
    return(NULL);
    # PPO server returns a 200 status code when results have been found with no server errors
  } else if (results$status_code == 200) {
    print ("unzipping response and processing data")
    bin <- httr::content(results, "raw")
    tf <- tempfile()

    # save file to disk
    writeBin(bin, tf)
    # read gzipped file and send to data frame
    # the first line in the returned file is a description of the query that we ran
    # the second line in the returned file is the header
    data <- read.csv(gzfile(tf),skip=1,header=TRUE)
    unlink(tf)
    return(data)
    # Something unexpected happened
  } else {
    print(paste("uncaught status code",results$status_code))
    warn_for_status(results)
    return(NULL);
  }
}

z_compact <- function(l) Filter(Negate(is.null), l)