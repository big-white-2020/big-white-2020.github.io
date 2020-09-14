#!/bin/bash
time=$(date "+%Y-%m-%d %H:%M:%S")
git add .
git commit -m "update ${time}"
git push origin modify
