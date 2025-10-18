#!/usr/bin/env bash

# VERSION=$(git describe --tags --abbrev=0)

jazzy \
    --clean \
    --author "Pete Richardson" \
    --github_url https://github.com/PeteRichardson/LabelKit \
    --module LabelKit
#    --github-file-prefix https://github.com/PeteRichardson/LabelKit/tree/$VERSION \
#    --module-version "$VERSION" 
