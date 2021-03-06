ggProportionPlot <- function(dat,
                             items,
                             loCategory = min(dat[, items], na.rm=TRUE),
                             hiCategory = max(dat[, items], na.rm=TRUE),
                             subQuestions = NULL,
                             leftAnchors = NULL,
                             rightAnchors = NULL,
                             compareHiToLo = TRUE,
                             showDiamonds = FALSE,
                             diamonds.conf.level=.95,
                             diamonds.alpha=1,
                             na.rm = TRUE,
                             barHeight = .4,
                             conf.steps = seq(from=0.0001, to=.9999, by=.0001),
                             scale_color = scale_color_viridis(option="magma", begin=0, end=.5),
                             scale_fill = scale_fill_viridis(option="magma", begin=0, end=.5),
                             theme = theme_bw()) {

  tmpDat <- dat[, items, drop=FALSE];
  if (na.rm) {
    tmpDat <- tmpDat[complete.cases(tmpDat), , drop=FALSE];
  }
  
  if (is.null(subQuestions)) {
    subQuestions <- items;
  }
  if (is.null(leftAnchors)) {
    leftAnchors <- rep(loCategory, length(items));
  }
  if (is.null(rightAnchors)) {
    if (compareHiToLo) {
      rightAnchors <- rep(hiCategory, length(items));
    } else {
      rightAnchors <- rep("Rest", length(items));
    }
  }

  if (ncol(tmpDat) == 1) {
    freqs <- data.frame(loCategoryCount = sum(tmpDat[, items] == loCategory));
  } else {
    freqs <- data.frame(loCategoryCount = colSums(tmpDat[, items] == loCategory));
  }

  if (compareHiToLo) {
    if (ncol(tmpDat) == 1) {
      freqs$totals <- sum(tmpDat[, items] == hiCategory) + freqs$loCategoryCount;
    } else {
      freqs$totals <- colSums(tmpDat[, items] == hiCategory) + freqs$loCategoryCount;
    }
  } else {
    freqs$totals <- rep(nrow(tmpDat), nrow(freqs));
  }

  confidences <- apply(freqs, 1, function(x) {
    #return(pbeta(conf.steps, x['loCategoryCount'], x['totals'] - x['loCategoryCount'] + 1));
    fullCIs <- confIntProp(x=x['loCategoryCount'],
                           n=x['totals'],
                           conf.level = conf.steps);
    return(c(rev(fullCIs[, 1]), fullCIs[, 2]));
  });
  
  ### Adjust confidence steps to conveniently generate
  ### a gradient. Add zero to the beginning to get the right
  ### number of intervals to draw the rectangles.
  conf.steps.adjusted <- c(0, conf.steps/2, rev(1-(conf.steps/2)));
  ### Get the beginning and end positions for the rectangles
  percentages.x1 <- rbind(c(0,0), 100*confidences);
  percentages.x2 <- rbind(100*confidences, c(100,100));

  longDat <- data.frame(Confidence=rep(conf.steps.adjusted, length(items)),
                        PercentageMin=as.vector(percentages.x1),
                        PercentageMax=as.vector(percentages.x2),
                        item=as.factor(rep(items, each=nrow(percentages.x1))));

  longDat$itemValue <- as.numeric(longDat$item);
  longDat$itemValueMin <- longDat$itemValue - barHeight;
  longDat$itemValueMax <- longDat$itemValue + barHeight;

  plot <- ggplot(longDat, aes_string(x='PercentageMin',
                                     y='itemValue')) +
    geom_rect(aes_string(xmin='PercentageMin',
                         xmax='PercentageMax',
                         ymin='itemValueMin',
                         ymax='itemValueMax',
                         color='Confidence',
                         fill='Confidence'),
                 show.legend=FALSE) +
    # geom_segment(aes_string(x='Percentage',
    #                         xend='Percentage',
    #                         y='itemValueMin',
    #                         yend='itemValueMax',
    #                         color='Confidence'),
    #              show.legend=FALSE) +
    scale_y_continuous(breaks=sort(unique(longDat$itemValue)),
                       minor_breaks = NULL,
                       labels=leftAnchors,
                       name=NULL,
                       sec.axis = dup_axis(labels=rightAnchors)) +
    coord_cartesian(xlim=c(0, 100)) +
    theme + scale_color + scale_fill;

  if (showDiamonds) {
    confInts <- t(apply(freqs, 1, function(x) {
        return(confIntProp(x['loCategoryCount'], x['totals'],
                           conf.level=diamonds.conf.level));
      }));
    colnames(confInts) <- c('ci.lo', 'ci.hi');
    confInts <- data.frame(100 * confInts);
    confInts$percentage <- 100 * freqs$loCategoryCount / freqs$totals;
    confInts <- confInts[, c(1,3,2)];
    confInts$otherAxisCol <- rev(1:length(items));
    plot <- plot + ggDiamondLayer(confInts,
                                  otherAxisCol='otherAxisCol',
                                  alpha=diamonds.alpha);
  }
  
  ### Create new version with subquestion labels
  suppressMessages(subQuestionLabelplot <- plot +
    scale_y_continuous(breaks=sort(unique(longDat$itemValue)),
                       minor_breaks = NULL,
                       name=NULL,
                       labels=subQuestions,
                       sec.axis=dup_axis(labels=subQuestions)) +
    theme(axis.text.y = element_text(size=rel(1.25), color="black"),
          axis.ticks.y = element_blank()));

  ### Extract grob with axis labels of secondary axis (at the right-hand side),
  ### which are the subquestions
  subQuestionLabelplotAsGrob <- ggplotGrob(subQuestionLabelplot);
  subQuestionPanel <- gtable_filter(subQuestionLabelplotAsGrob, "axis-r");
  
  ### Compute how wide this grob is based on the width of the
  ### widest element, and express this in inches
  maxSubQuestionWidth <- max(unlist(lapply(lapply(unlist(strsplit(subQuestions, "\n")),
                                                  unit, x=1, units="strwidth"), convertUnit, "inches")));
  
  ### Convert the real plot to a gtable
  plotAsGrob <- ggplotGrob(plot);
  
  index <- which(subQuestionLabelplotAsGrob$layout$name == "axis-r");
  subQuestionWidth <-
    subQuestionLabelplotAsGrob$widths[subQuestionLabelplotAsGrob$layout[index, ]$l];
  
  ### Add a column to the left, with the width of the subquestion grob
  fullPlot <- gtable_add_cols(plotAsGrob, subQuestionWidth, pos=0);
  
  ### Get the layout information of the panel to locate the subquestion
  ### grob at the right height (i.e. in the right row)
  index <- plotAsGrob$layout[plotAsGrob$layout$name == "panel", ];
  
  ### Add the subquestion grob to the plot
  fullPlot <- gtable_add_grob(fullPlot,
                              subQuestionPanel,
                              t=index$t, l=1, b=index$b, r=1,
                              name = "subquestions");

  grid.newpage();
  grid.draw(fullPlot);
}

# confIntProp(sum(mtcars$vs), nrow(mtcars));
# confIntProp(sum(mtcars$am), nrow(mtcars));
bigmtcars <- mtcars[sample(1:nrow(mtcars), 800, replace = TRUE), ];

ggProportionPlot(mtcars, items=c('vs', 'am'), showDiamonds = FALSE);

#ggProportionPlot(bigmtcars, items=c('vs', 'am'), showDiamonds = FALSE);
