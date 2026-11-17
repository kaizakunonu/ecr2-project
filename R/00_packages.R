
# Packages used in the DRC sentinel-site analysis

library(sf)        # Vector data: site points, province and health-zone boundaries
library(terra)     # Modern raster handling: crop, aggregate and area summaries of travel-time surfaces
library(raster)    # Legacy raster format that gdistance requires for the friction surfaces
library(gdistance) # Cost-distance on the friction surface: transition layers, travel times, least-cost routes
library(dplyr)     # Data manipulation: filter, mutate, join and summarise tables
library(tidyr)     # Reshape tables between wide and long formats
library(readr)     # Fast reading and writing of CSV inputs and result tables
library(ggplot2)   # Static maps and figures for the report and poster
library(ggrepel)   # Non-overlapping site labels on ggplot2 maps
library(igraph)    # Graph algorithms that gdistance uses for shortest-path routing
library(jsonlite)  # Read and write JSON, e.g. GRID3 ArcGIS service responses
