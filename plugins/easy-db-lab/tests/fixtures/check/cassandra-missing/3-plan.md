# Lab Plan: Scrape allocation with the canary

## Objective

Find out if the canary build allocates less on the metrics scrape path than stock.

## Steps

### 1. Measure scrape allocation

Run `easy-db-lab cassandra use 5.0` on each arm.  Then run the scrape load for ten minutes.
