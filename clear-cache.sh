#!/bin/bash

# Find files in ~/.cache that have not been accessed for more than 180 days
# find ~/.cache/ -depth -type f -atime +180

# Find and delete files in ~/.cache that have not been accessed for more than 365 days
find ~/.cache/ -type f -atime +365 -delete
