# Launch xcmsVisGUI.

Performs the one-time runtime setup (mirai daemon pool, large-upload
option; SerialParam is registered on package load) and starts the Shiny
app. The daemon pool is torn down when the app stops.

## Usage

``` r
run_app(...)
```

## Arguments

- ...:

  passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html) (e.g.
  `port`, `launch.browser`).

## Value

Invisibly, the result of
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

## Examples

``` r
if (interactive()) run_app()
```
