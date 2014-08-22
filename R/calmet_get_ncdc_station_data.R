#' Obtain NCDC station data
#' @description Obtain NCDC station data for all stations residing in the CALMET domain during a specied time period.
#' @param start_year the year for the start of data retrieval.
#' @param end_year the year for the end of data retrieval.
#' @param bbox_lat_lon a spatial bounding box in projected in lat/lon coordinates
#' @export calmet_get_ncdc_station_data
#' @examples
#' \dontrun{
#' # Get 2010 station data for a previously defined domain
#' calmet_get_ncdc_station_data(start_year = 2010,
#'                              end_year = 2010,
#'                              bbox_lat_lon = bbox)
#'}

calmet_get_ncdc_station_data <- function(start_year = NULL,
                                         end_year = NULL,
                                         bbox_lat_lon = NULL){
  
  # Add require statements
  require(lubridate)
  require(plyr)
  require(stringr)
  
  # Check whether 'start_year' and 'end_year' are both provided
  if (is.null(start_year) | is.null(end_year)) {
    stop("Please enter starting and ending years for surface station data")
  } else { }
  
  # Check whether 'start_year' and 'end_year' are both numeric
  if (!is.numeric(start_year) | !is.numeric(end_year)) {
    stop("Please enter numeric values for the starting and ending years")
  } else { }
  
  # Check whether 'start_year' and 'end_year' are in the correct order
  if (start_year > end_year) {
    stop("Please enter the starting and ending years in the correct order")
  } else { }
  
  # Check whether 'staryear' and 'end_year' are within set bounds (1950 to current year)
  if (start_year < 1892 | end_year < 1892 | start_year > year(Sys.Date()) | end_year > year(Sys.Date())) {
    stop("Please enter the starting and ending years in the correct order")
  } else { }
  
  # Get hourly surface data history CSV from NOAA/NCDC FTP
  calmet_get_ncdc_history()
  
  # Read in the 'ish-history.csv' file
  st <- read.csv("ish-history.csv")
  
  # Get formatted list of station names and elevations
  names(st)[c(3, 10)] <- c("NAME", "ELEV")
  st <- st[, -5]
  
  # Reintroduce the decimals in the latitude, longitude, and elevation
  st$LAT <- st$LAT/1000
  st$LON <- st$LON/1000
  st$ELEV <- st$ELEV/10
  
  # Recompose the years from the data file
  st$BEGIN <- as.numeric(substr(st$BEGIN, 1, 4))
  st$END <- as.numeric(substr(st$END, 1, 4))
  
  # Generate a list based on the domain location, also ignoring stations
  # without beginning years reported
  domain.list <- subset(st, st$LON >= bbox_lat_lon@xmin & 
                          st$LON <= bbox_lat_lon@xmax &
                          st$LAT >= bbox_lat_lon@ymin &
                          st$LAT <= bbox_lat_lon@ymax &
                          BEGIN <= start_year - 1 &
                          END >= end_year + 1)
  
  # Initialize data frame for file status reporting
  outputs <- as.data.frame(matrix(NA, dim(domain.list)[1], 2))
  names(outputs) <- c("FILE", "STATUS")
  
  # Download the gzip-compressed data files for the years specified
  # Provide information on the number of records in data file retrieved 
  for (y in (start_year - 1):(end_year + 1)){
    
    y.domain.list <- domain.list[domain.list$BEGIN <= y & domain.list$END >= y, ]
    
    for (s in 1:dim(y.domain.list)[1]) {
      
      outputs[s, 1] <- paste(sprintf("%06d", y.domain.list[s,1]),
                             "-", sprintf("%05d", y.domain.list[s,2]),
                             "-", y, ".gz", sep = "")
      
      system(paste("curl -O ftp://ftp.ncdc.noaa.gov/pub/data/noaa/", y,
                   "/", outputs[s, 1], sep = ""))
      
      outputs[s, 2] <- ifelse(file.exists(outputs[s, 1]) == "TRUE", 'available', 'missing')
      
    }
    
  }
  
  # Generate report of stations and file transfers
  file_report <- cbind(y.domain.list, outputs)
  row.names(file_report) <- 1:nrow(file_report)
  
  # Extract all downloaded data files
  system("gunzip *.gz", intern = FALSE, ignore.stderr = TRUE)
  
  # Read data from files
  # Specific focus here is on the fixed width portions ('Mandatory Data Section') of each file
  files <- list.files(pattern = "^[0-9]*-[0-9]*-[0-9]*$")
  column.widths <- c(4, 6, 5, 4, 2, 2, 2, 2, 1, 6,
                     7, 5, 5, 5, 4, 3, 1, 1, 4, 1,
                     5, 1, 1, 1, 6, 1, 1, 1, 5, 1,
                     5, 1, 5, 1)
  stations <- as.data.frame(matrix(NA, length(files), 6))
  names(stations) <- c("USAFID", "WBAN", "YR", "LAT", "LONG", "ELEV")
  
  for (i in 1:length(files)) {
    
    # Read data from mandatory data section of each file, which is a fixed-width string
    data <- read.fwf(files[i], column.widths)
    data <- data[, c(2:8, 10:11, 13, 16, 19, 21, 29, 31, 33)]
    names(data) <- c("USAFID", "WBAN", "YR", "M", "D", "HR", "MIN", "LAT", "LONG",
                     "ELEV", "WIND.DIR", "WIND.SPD", "CEIL.HGT", "TEMP", "DEW.POINT",
                     "ATM.PRES")
    
    # Recompose data and use consistent missing indicators of 9999 for missing data
    data$LAT <- data$LAT/1000
    data$LONG <- data$LONG/1000
    data$WIND.DIR <- ifelse(data$WIND.DIR == 999, 999, data$WIND.DIR)
    data$WIND.SPD <- ifelse(data$WIND.SPD > 100, 999.9, data$WIND.SPD/10)
    data$TEMP <-  ifelse(data$TEMP > 900, 999.9, round((data$TEMP/10) + 273.2, 1))
    data$DEW.POINT <- ifelse(data$DEW.POINT > 100, 999.9, data$DEW.POINT/10)
    data$ATM.PRES <- ifelse(data$ATM.PRES > 2000, 999.9, data$ATM.PRES/10)
    data$CEIL.HGT <- ifelse(data$CEIL.HGT == 99999, 999.9, round(data$CEIL.HGT*3.28084/100, 0))
    
    # Read data from additional data section of each file
    # Additional data is of variable length and may not exist in every line of every file
    additional.data <- as.data.frame(scan(files[i], what = 'character', sep = "\n"))
    colnames(additional.data) <- c("string")
    number_of_add_lines <- sum(str_detect(additional.data$string, "ADD"), na.rm = TRUE)
    percentage_of_add_lines <- (number_of_add_lines/length(additional.data$string)) * 100
    
    # opaque sky cover: GF1
    number_of_sky_cover_lines <- sum(str_detect(additional.data$string, "GF1"), na.rm = TRUE)
    percentage_of_sky_cover_lines <- (number_of_sky_cover_lines/length(additional.data$string)) * 100
    
    if (number_of_sky_cover_lines > 0) {      
      GF1_sky_cover_coverage_code <- as.character(str_extract_all(additional.data$string, "GF1[0-9][0-9]"))
      GF1_sky_cover_coverage_code <- str_replace_all(GF1_sky_cover_coverage_code,
                                                     "GF1([0-9][0-9])", "\\1")
      GF1_sky_cover_coverage_code <- as.numeric(GF1_sky_cover_coverage_code)  
    }
    
    # precipitation: AA[1-2]
    number_of_precip_lines <- sum(str_detect(additional.data$string, "AA1"), na.rm = TRUE)
    percentage_of_precip_lines <- (number_of_precip_lines/length(additional.data$string)) * 100
    
    if (number_of_precip_lines > 0) {      
      AA1_precip_period_in_hours <- as.character(str_extract_all(additional.data$string, "AA1[0-9][0-9]"))
      AA1_precip_period_in_hours <- str_replace_all(AA1_precip_period_in_hours,
                                                    "AA1([0-9][0-9])", "\\1")
      AA1_precip_period_in_hours <- as.numeric(AA1_precip_period_in_hours)     
      AA1_precip_depth_in_mm <- as.character(str_extract_all(additional.data$string,
                                                             "AA1[0-9][0-9][0-9][0-9][0-9][0-9]"))
      AA1_precip_depth_in_mm <- str_replace_all(AA1_precip_depth_in_mm,
                                                "AA1[0-9][0-9]([0-9][0-9][0-9][0-9])", "\\1")
      AA1_precip_depth_in_mm <- as.numeric(AA1_precip_depth_in_mm)/10
      AA1_precip_rate_in_mm_per_hour <- AA1_precip_depth_in_mm / AA1_precip_period_in_hours      
      additional.data$PRECIP.RATE <- round_any(AA1_precip_rate_in_mm_per_hour, 0.1, f = round)      
    } 
    
    if (number_of_precip_lines == 0) {
      # put in vector of NAs in PRECIP.RATE column of data frame
      additional.data$PRECIP.RATE <- rep(NA, length(additional.data$string))
    }
    
    # Remove the string portion of the 'additional data' data frame
    additional.data$string <- NULL
    
    # Column bind the 'data' and 'additional data' data frame
    data <- cbind(data, additional.data)
    
    # Calculate the RH using the August-Roche-Magnus approximation
    RH <- ifelse(data$TEMP == 999.9 | data$DEW.POINT == 999.9, NA, 
                 100 * (exp((17.625 * data$DEW.POINT) / (243.04 + data$DEW.POINT))/
                          exp((17.625 * (data$TEMP - 273.2)) / (243.04 + (data$TEMP - 273.2)))))
    
    data$RH <- round_any(as.numeric(RH), 0.1, f = round)
    
    # Calculate the precipitation code
    # 
    # Category        Temperature   Rate (mm/hr)    Code
    # -------------   -----------   -------------   ----
    # Light Rain      >0 deg C      R < 2.5         1
    # Moderate Rain   >0 deg C      2.5 ≤ R < 7.6   2
    # Heavy Rain      >0 deg C      R ≤ 7.6         3
    # Light Snow      <=0 deg C     R < 2.5         19
    # Moderate Snow   <=0 deg C     2.5 ≤ R < 7.6   20
    # Heavy Snow      <=0 deg C     R ≤ 7.6         21
    
    PRECIP.CODE <- with(data, ifelse(PRECIP.RATE > 0 & PRECIP.RATE < 2.5, 1,
                                     ifelse(PRECIP.RATE >= 2.5 & PRECIP.RATE < 7.6, 2,
                                            ifelse(PRECIP.RATE >= 7.6, 3, 9999))))
    
    PRECIP.CODE <- ifelse(PRECIP.CODE < 25 & data$TEMP < 273.2, PRECIP.CODE + 18, PRECIP.CODE)
    
    # Add precipitation code to the data frame
    data$PRECIP.CODE <- PRECIP.CODE
    
    # Write CSV file for each station, combining data elements from the mandatory data
    # section and the additional data section
    write.csv(data, file = paste(files[i], ".csv", sep = ""), row.names = FALSE)
    
    # Create a data frame with summary data for each station
    stations[i, 1:3] <- data[1, 1:3]
    stations[i, 4:6] <- data[1, 8:10]
    
  }
  
  # Write the station data to a CSV file
  write.csv(stations, file = "stations.csv", row.names = FALSE)
    
}