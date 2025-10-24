# MinuteMetrics

MinuteMetrics is a lightweight web service designed to provide both dynamic and static data. The dynamic data changes based on a predefined schedule, while the static data can be set and updated as needed. The application serves simple JSON responses that include a name and a value, with the value changing over time according to user-defined settings.

## Features

- Dynamic value updates based on a customizable schedule.
- Static value endpoint for setting and updating a fixed value.
- Configurable through both environment variables and command-line arguments.
- Simple RESTful endpoints to fetch and update current values.

## Configuration

MinuteMetrics can be configured using command-line arguments or environment variables. Command-line arguments take precedence over environment variables.

### Command-Line Arguments

- `-base`: Sets the initial base value for calculations. Overrides the `BASE` environment variable if provided.
- `-multiplier` Similar to `base`, it scales the values by a factor. This is applied before adding the `base`. Overrides `MULTIPLIER` if provided.
- `-lazy-start`: Enables lazy start, delaying the schedule's start until the first request is received. Overrides the `LAZY_START` environment variable if provided.
- `-schedule`: Defines the value update schedule in a `minute:value` pairs format. Overrides the `SCHEDULE` environment variable if provided.
- `-cycle-minutes`: Repeat provided schedule every N minutes provided by this variable.
- `-static-value`: Sets the initial static value for static metrics. Overrides the `STATIC_VALUE` environment variable if provided.
- `-time-relative-to-start`: When enabled (default), it will use the time app is running for its calculations. Disabled takes the UTC time of a day - # of minutes since midnight. Overrides `TIME_RELATIVE_TO_START` if provided
- `-interpolate-values`: When enabled, it will interpolate the values between each schedule items. Overrides `INTERPOLATE_VALUES` if provided.
- `-help`: Displays help information about the application usage and options.

### Environment Variables

- `BASE`: Sets the initial base value for calculations.
- `MULTIPLIER`: See cmd arg `-multiplier`. Takes a float.
- `LAZY_START`: Enables lazy start with "true".
- `SCHEDULE`: Defines the value update schedule in a `minute:value` pairs format.
- `TIME_RELATIVE_TO_START`: See cmd arg `-time-relative-to-start`. Disables with "false" (enabled by default).
- `INTERPOLATE_VALUES`: See cmd arg `-interpolate-values`. Enables with "true".
- `STATIC_VALUE`: Sets the initial static value for static metrics.

## Endpoint

- `/api/v1/minutemetrics`: Returns the current name and value in JSON format. Example response:

```json
{
  "name": "minute-metrics",
  "value": 10
}
```
- `/api/v1/staticmetrics`: GET returns the current static metric data in JSON format. PUT updates the static metric value.
```json
{
  "name": "static-metrics",
  "value": 5
}
```

## Schedule Examples

Schedules are defined as comma-separated `minute:value` pairs, where `minute` is the minute within a 10-minute cycle, and `value` is the value to be returned starting from that minute.

### Example 1: Constant Increase

- Schedule: `"0:10,1:20,2:30,3:40,4:50,5:60,6:70,7:80,8:90,9:100"`
- Behavior: The value starts at 10 at the beginning of the cycle and increases by 10 every minute, reaching 100 at the 9th minute.

### Example 2: Specific Changes

- Schedule: `"0:10,3:0,7:50"`
- Behavior: The value starts at 10, changes to 0 at the 3rd minute, and then to 50 at the 7th minute.

### Example 3: Reset Mid-Cycle

- Schedule: `"0:5,5:0"`
- Behavior: The value starts at 5 and resets to 0 at the 5th minute of the cycle.

### Example 4: Return number of minutes in a day multiplied by 3 and add 42 to it

```bash
go run . -cycle-minutes $[24*60] -base 42 -multiplier 3 -interpolate-values -time-relative-to-start=false -schedule "0:0,1440:1440"
```

## Running MinuteMetrics

To run MinuteMetrics with a specific base value and schedule, you might use:

```sh
go run . -base 5 -lazy-start -schedule "0:10,5:20"
```

This sets the initial value to 5, enables lazy start, and uses a schedule where the value starts at 10 and changes to 20 at the 5th minute of every 10-minute cycle.


To set or update the static value at runtime, use the following curl command:
```bash
curl -X PUT -H "Content-Type: application/json" -d '{"value":5}' http://localhost:8080/api/v1/staticmetrics
```
