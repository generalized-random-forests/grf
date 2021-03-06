library(grf)

test_that("single treatment multi_arm_causal_forest is similar to causal_forest", {
  # It is not possible to check this parity holds exactly since forest differences
  # accrue through numerical differences (e.g. relabeling in causal forest is done with doubles
  # and with Eigen data structures in multi arm causal forest.)
  n <- 500
  p <- 5
  X <- matrix(rnorm(n * p), n, p)
  W <- rbinom(n, 1, 0.5)
  tau <- pmax(X[, 1], 0)
  Y <- tau * W + X[, 2] + pmin(X[, 3], 0) + rnorm(n)
  nmissing <- 50
  X[cbind(sample(1:n, nmissing), sample(1:p, nmissing, replace = TRUE))] <- NaN

  cf <- causal_forest(X, Y, W, W.hat = 1/2, Y.hat = 0, seed = 42, stabilize.splits = FALSE,
                     alpha = 0, min.node.size = 1, num.trees = 500)
  mcf <- multi_arm_causal_forest(X, Y, as.factor(W), W.hat = c(1/2, 1/2), Y.hat = 0, seed = 42,
                                 alpha = 0, min.node.size = 1, num.trees = 500)

  pp.cf <- predict(cf, estimate.variance = TRUE)
  pp.mcf <- predict(mcf, estimate.variance = TRUE)
  z.cf <- abs((pp.cf$predictions - tau) / sqrt(pp.cf$variance.estimates))
  z.mcf <- abs((pp.mcf$predictions[,,] - tau) / sqrt(pp.mcf$variance.estimates))
  expect_equal(mean(z.cf > 1.96), mean(z.mcf > 1.96), tol = 0.05)

  expect_equal(mean((pp.cf$predictions - pp.mcf$predictions)^2), 0, tol = 0.05)
  expect_equal(mean(pp.cf$predictions), mean(pp.mcf$predictions), tol = 0.05)

  expect_equal(mean((predict(cf, X)$predictions - predict(mcf, X)$predictions)^2), 0, tol = 0.05)
  expect_equal(mean(predict(cf, X)$predictions), mean(predict(mcf, X)$predictions), tol = 0.05)

  expect_equal(average_treatment_effect(cf), average_treatment_effect(mcf)[,], tol = 0.001)
})

test_that("multi_arm_causal_forest contrasts works as expected", {
  n <- 500
  p <- 5
  X <- matrix(rnorm(n * p), n, p)
  W <- as.factor(sample(c("A", "B", "C"), n, replace = TRUE))
  Y <- X[, 1] + 1.5 * (W == "A") + 2.8 * (W == "B") - 4 * (W == "C") + 0.1 * rnorm(n)

  mcf.A <- multi_arm_causal_forest(X, Y, W, num.trees = 500, seed = 42)
  tau.hat.oob.A <- predict(mcf.A)$predictions[,,]
  tau.hat.A <- predict(mcf.A, X)$predictions[,,]

  mcf.C <- multi_arm_causal_forest(X, Y, relevel(W, ref = "C"), num.trees = 500, seed = 42)
  tau.hat.oob.C <- predict(mcf.C)$predictions[,,]
  tau.hat.C <- predict(mcf.C, X)$predictions[,,]

  # 1. With easy constant treatment effects we estimate the correct contrasts
  expect_equal(colMeans(tau.hat.oob.A), c("B - A" = 2.8 - 1.5, "C - A" = -4 - 1.5), tol = 0.04)
  expect_equal(colMeans(tau.hat.A), c("B - A" = 2.8 - 1.5, "C - A" = -4 - 1.5), tol = 0.04)
  expect_equal(colMeans(tau.hat.oob.C), c("A - C" = 1.5 - (-4), "B - C" = 2.8 - (-4)), tol = 0.04)
  expect_equal(colMeans(tau.hat.C), c("A - C" = 1.5 - (-4), "B - C" = 2.8 - (-4)), tol = 0.04)

  # 2. The estimated contrast respects the symmetry properties we expect. It is not possible to check
  # this invariant exactly since differences in relabeling may lead to different trees
  expect_equal(tau.hat.oob.A[, "C - A"], -1 * tau.hat.oob.C[, "A - C"], tol = 0.01)
  expect_equal(tau.hat.A[, "C - A"], -1 * tau.hat.C[, "A - C"], tol = 0.01)

  expect_equal(tau.hat.oob.A[, "B - A"] - tau.hat.oob.A[, "C - A"], tau.hat.oob.C[, "B - C"], tol = 0.01)
  expect_equal(tau.hat.A[, "B - A"] - tau.hat.A[, "C - A"], tau.hat.C[, "B - C"], tol = 0.01)

  # The above invariance holds exactly if we ignore splitting and just predict
  mcf.A.ns <- multi_arm_causal_forest(X, Y, W, num.trees = 250, seed = 42, min.node.size = n)
  tau.hat.oob.A.ns <- predict(mcf.A.ns)$predictions[,,]
  tau.hat.A.ns <- predict(mcf.A.ns, X)$predictions[,,]

  mcf.C.ns <- multi_arm_causal_forest(X, Y, relevel(W, ref = "C"), num.trees = 250, seed = 42, min.node.size = n)
  tau.hat.oob.C.ns <- predict(mcf.C.ns)$predictions[,,]
  tau.hat.C.ns <- predict(mcf.C.ns, X)$predictions[,,]

  expect_equal(tau.hat.oob.A.ns[, "C - A"], -1 * tau.hat.oob.C.ns[, "A - C"], tol = 1e-10)
  expect_equal(tau.hat.A.ns[, "C - A"], -1 * tau.hat.C.ns[, "A - C"], tol = 1e-10)

  expect_equal(tau.hat.oob.A.ns[, "B - A"] - tau.hat.oob.A.ns[, "C - A"], tau.hat.oob.C.ns[, "B - C"], tol = 1e-10)
  expect_equal(tau.hat.A.ns[, "B - A"] - tau.hat.A.ns[, "C - A"], tau.hat.C.ns[, "B - C"], tol = 1e-10)
})

test_that("multi_arm_causal_forest with binary treatment respects contrast invariance", {
  n <- 500
  p <- 5
  X <- matrix(rnorm(n * p), n, p)
  W <- rbinom(n, 1, 0.5)
  Y <- pmax(X[, 1], 0) * W + X[, 2] + pmin(X[, 3], 0) + rnorm(n)

  # With W.hat = 1/2 we can make the following check exact.
  # Setting W.hat to NULL or any other float pair will cause extremely small numerical differences
  # to accrue (10th+ digit) in splitting on the pseudo outcomes, leading these forests
  # to yield different splits even though they are algebraically the same.
  W.hat <- c(0.5, 0.5)
  cf <- multi_arm_causal_forest(X, Y, as.factor(W), W.hat = W.hat, num.trees = 250, seed = 42)
  cf.flipped <- multi_arm_causal_forest(X, Y, as.factor(1 - W), W.hat = W.hat, num.trees = 250, seed = 42)
  cf.relevel <- multi_arm_causal_forest(X, Y, relevel(as.factor(W), ref = "1"), W.hat = W.hat, num.trees = 250, seed = 42)

  pp <- predict(cf)$predictions[,,]
  pp.flipped <- predict(cf.flipped)$predictions[,,]
  pp.relevel <- predict(cf.relevel)$predictions[,,]

  expect_equal(pp, -1 * pp.flipped, tol = 0)
  expect_equal(pp, -1 * pp.relevel, tol = 0)
  expect_equal(pp.flipped, pp.relevel, tol = 0)
})

test_that("multi_arm_causal_forest ATE works as expected", {
  n <- 500
  p <- 5
  X <- matrix(rnorm(n * p), n, p)
  W <- as.factor(sample(c("A", "B", "C"), n, replace = TRUE))
  tauB <- pmax(X[, 2], 0)
  tauC <- - 1.5 * abs(X[, 2])
  Y <- 2 + X[, 1] + tauB * (W == "B") + tauC * (W == "C") + 0.1 * rnorm(n)
  mcf <- multi_arm_causal_forest(X, Y, W, num.trees = 500)

  ate <- average_treatment_effect(mcf)
  expect_equal(ate["B - A", "estimate"], mean(tauB), tol = 3 * ate["B - A", "std.err"])
  expect_equal(ate["C - A", "estimate"], mean(tauC), tol = 3 * ate["C - A", "std.err"])

  ate.subset <- average_treatment_effect(mcf, subset = X[, 2] < 0)
  expect_equal(ate.subset["B - A", "estimate"], 0, tol = 3 * ate.subset["B - A", "std.err"])

  mcf.B <- multi_arm_causal_forest(X, Y, relevel(W, ref = "B"), num.trees = 500)
  ate.B <- average_treatment_effect(mcf.B)

  expect_equal(ate.B["A - B", "estimate"], -1 * ate["B - A", "estimate"], tol = 0.05)
  expect_equal(ate.B["C - B", "estimate"], ate["C - A", "estimate"] - ate["B - A", "estimate"], tol = 0.05)
})

test_that("multi_arm_causal_forest predictions are kernel weighted correctly", {
  n <- 250
  p <- 5
  X <- matrix(rnorm(n * p), n, p)
  W <- as.factor(sample(c("A", "B", "C"), n, replace = TRUE))
  tauB <- pmax(X[, 2], 0)
  tauC <- - 1.5 * abs(X[, 2])
  Y <- 2 + X[, 1] + tauB * (W == "B") + tauC * (W == "C") + rnorm(n)
  sample.weights <- sample(c(1, 5), n, TRUE)
  mcf <- multi_arm_causal_forest(X, Y, W, Y.hat = 0, W.hat = c(0, 0, 0), num.trees = 250)
  mcf.weighted <- multi_arm_causal_forest(X, Y, W, Y.hat = 0, W.hat = c(0, 0, 0), num.trees = 250, sample.weights = sample.weights)

  W.matrix <- stats::model.matrix(~ mcf$W.orig - 1)
  x1 <- X[1, , drop = F]
  theta1 <- predict(mcf, x1)$predictions
  alpha1 <- get_sample_weights(mcf, x1)[1, ]
  theta1.lm <- lm(Y ~ W.matrix[, -1], weights = alpha1)

  theta1.weighted <- predict(mcf.weighted, x1)$predictions
  alpha1.weighted <- get_sample_weights(mcf.weighted, x1)[1, ]
  theta1.lm.weighted <- lm(Y ~ W.matrix[, -1], weights = alpha1.weighted * sample.weights)

  expect_equal(as.numeric(theta1), as.numeric(theta1.lm$coefficients[-1]), tol = 1e-6)
  expect_equal(as.numeric(theta1.weighted), as.numeric(theta1.lm.weighted$coefficients[-1]), tol = 1e-6)
})

test_that("multi_arm_causal_forest predictions and variance estimates are invariant to scaling of the sample weights.", {
  n <- 250
  p <- 5
  X <- matrix(rnorm(n * p), n, p)
  W <- as.factor(sample(c("A", "B", "C"), n, replace = TRUE))
  tauB <- pmax(X[, 2], 0)
  tauC <- - 1.5 * abs(X[, 2])
  Y <- 2 + X[, 1] + tauB * (W == "B") + tauC * (W == "C") + rnorm(n)
  sample.weights <- sample(c(1, 5), n, TRUE)

  # The multiple is a power of 2 to avoid rounding errors allowing for exact comparison
  # between two forest with the same seed.
  forest.1 <- multi_arm_causal_forest(X, Y, W, sample.weights = sample.weights, num.trees = 250, seed = 42)
  forest.2 <- multi_arm_causal_forest(X, Y, W, sample.weights = 64 * sample.weights, num.trees = 250, seed = 42)
  pred.1 <- predict(forest.1, estimate.variance = TRUE)
  pred.2 <- predict(forest.2, estimate.variance = TRUE)

  expect_equal(pred.1$predictions, pred.2$predictions, tol = 1e-10)
  # expect_equal(pred.1$variance.estimates, pred.2$variance.estimates, tol = 1e-10)
  # expect_equal(pred.1$debiased.error, pred.2$debiased.error, tol = 1e-10)
})

test_that("multi_arm_causal_forest confidence intervals are reasonable", {
  n <- 500
  p <- 5
  X <- matrix(rnorm(n * p), n, p)
  W <- as.factor(sample(c("A", "B", "C"), n, replace = TRUE))
  tauB <- pmax(X[, 2], 0)
  tauC <- - 1.5 * abs(X[, 2])
  Y <- 2 + X[, 1] + tauB * (W == "B") + tauC * (W == "C") + rnorm(n)
  mcf <- multi_arm_causal_forest(X, Y, W, num.trees = 500)

  tau <- cbind(tauB, tauC)
  pp.mcf <- predict(mcf, estimate.variance = TRUE)
  z <- abs((pp.mcf$predictions[,,] - tau) / sqrt(pp.mcf$variance.estimates))

  expect_true(all(colMeans(z > 1.96) < c(0.25, 0.25)))
})

test_that("multi_arm_causal_forest with multiple outcomes works as expected", {
  n <- 500
  p <- 5
  X <- matrix(rnorm(n * p), n, p)
  W <- as.factor(sample(c("A", "B", "C"), n, replace = TRUE))
  Y <- X[, 1] + X[, 2] * (W == "B") - 1.5 * X[, 2] * (W == "C") + rnorm(n)
  nmissing <- 50
  X[cbind(sample(1:n, nmissing), sample(1:p, nmissing, replace = TRUE))] <- NaN

  # Check various symmetry properties.
  # A multi arm causal forest trained on Y is identical to one trained on [Y 0]
  rf <- multi_arm_causal_forest(X, Y, W, Y.hat = 0, W.hat = c(1/3, 1/3, 1/3),
                                num.trees = 200, seed = 42)
  mrf <- multi_arm_causal_forest(X, cbind(Y, 0), W, Y.hat = c(0, 0), W.hat = c(1/3, 1/3, 1/3),
                                 num.trees = 200, seed = 42)

  expect_equal(predict(rf)$predictions[,,], predict(mrf)$predictions[, , 1])
  expect_equal(predict(rf, X)$predictions[,,], predict(mrf, X)$predictions[, , 1])
  expect_equal(dim(predict(mrf)$predictions), c(n, 2, 2))
  expect_equal(average_treatment_effect(rf), average_treatment_effect(mrf))

  # The above logic holds "symmetrically"
  # A multi arm causal forest trained on Y is identical to one trained on [0 Y]
  mrf <- multi_arm_causal_forest(X, cbind(0, Y), W, Y.hat = c(0, 0), W.hat = c(1/3, 1/3, 1/3),
                                 num.trees = 200, seed = 42)

  expect_equal(predict(rf)$predictions[,,], predict(mrf)$predictions[, , 2])
  expect_equal(predict(rf, X)$predictions[,,], predict(mrf, X)$predictions[, , 2])
  expect_equal(dim(predict(mrf)$predictions), c(n, 2, 2))
  expect_equal(average_treatment_effect(rf), average_treatment_effect(mrf, outcome = 2))

  # A multi arm causal forest trained on Y is identical to one trained on [0 0 Y 0 0 0]
  mrf <- multi_arm_causal_forest(X, cbind(0, 0, Y, 0, 0, 0), W, Y.hat = rep(0, 6), W.hat = c(1/3, 1/3, 1/3),
                                 num.trees = 200, seed = 42)

  expect_equal(predict(rf)$predictions[,,], predict(mrf)$predictions[, , 3])
  expect_equal(predict(rf, X)$predictions[,,], predict(mrf, X)$predictions[, , 3])
  expect_equal(dim(predict(mrf)$predictions), c(n, 2, 6))
  expect_equal(average_treatment_effect(rf), average_treatment_effect(mrf, outcome = 3))

  # A multi arm causal forest trained on duplicated Y's yields the same result
  n <- 500
  p <- 5
  X <- matrix(rnorm(n * p), n, p)
  W <- as.factor(sample(c("A", "B", "C"), n, replace = TRUE))
  YY <- X[, 1] + X[, 2] * (W == "B") - 1.5 * X[, 2] * (W == "C") + matrix(rnorm(n * 2), n, 2)
  colnames(YY) <- 1:2
  mrf <- multi_arm_causal_forest(X, YY, W, Y.hat = c(0, 0), W.hat = c(1/3, 1/3, 1/3),
                                 num.trees = 200, seed = 42)
  mrf.dup <- multi_arm_causal_forest(X, cbind(YY, YY), W, Y.hat = rep(0, 4), W.hat = c(1/3, 1/3, 1/3),
                                     num.trees = 200, seed = 42)

  expect_equal(predict(mrf)$predictions, predict(mrf.dup)$predictions[, , 1:2])
  expect_equal(predict(mrf)$predictions, predict(mrf.dup)$predictions[, , 3:4])
  expect_equal(average_treatment_effect(mrf, outcome = 1), average_treatment_effect(mrf.dup, outcome = 1))
  expect_equal(average_treatment_effect(mrf, outcome = 1), average_treatment_effect(mrf.dup, outcome = 3))
  expect_equal(average_treatment_effect(mrf, outcome = 2), average_treatment_effect(mrf.dup, outcome = 2))
  expect_equal(average_treatment_effect(mrf, outcome = 2), average_treatment_effect(mrf.dup, outcome = 4))
})

test_that("multi_arm_causal_forest with multiple outcomes is well calibrated", {
  # Simulate n correlated mean zero normal draws with covariance matrix sigma
  # using the Cholesky decomposition. Returns a [n X ncol(sigma)] matrix.
  rmvnorm <- function(n, sigma) {
    K <- ncol(sigma)
    A <- chol(sigma)
    z <- matrix(rnorm(n * K), n, K)
    z %*% A
  }

  # A multi arm causal forest fit on two outcomes yields lower MSE than two separate
  # causal forests when the CATEs are correlated with low idiosyncratic noise.
  sigma <- diag(4)
  sigma[2, 1] <- sigma[1, 2] <- 0.5
  sigma[3, 4] <- sigma[4, 3] <- 0.5

  n <- 500
  p <- 4
  X <- rmvnorm(n, sigma = sigma)
  W <- rbinom(n, 1, 0.5)
  tau1 <- pmax(X[, 1], 0)
  tau2 <- pmax(X[, 2], 0)
  tau <- cbind(tau1, tau2)
  YY <- tau * W + X[, 3:4] + 0.5 * matrix(rnorm(n * 2), n, 2)

  cf.pred <- apply(YY, 2, function(Y) predict(causal_forest(X, Y, W, num.trees = 500, stabilize.splits = FALSE))$predictions)
  mcf.pred <- predict(multi_arm_causal_forest(X, YY, as.factor(W), num.trees = 500))$predictions[,,]
  mse.cf <- mean((mcf.pred - tau)^2)
  mse.mcf <- mean((cf.pred - tau)^2)

  expect_lt(mse.mcf / mse.cf,  0.85)
})
