#!/usr/bin/env bash

set -euo pipefail

NUMBER_OF_EXECUTIONS=10
if [[ "$#" -eq 1 ]]; then
    NUMBER_OF_EXECUTIONS=$1
fi

function colorize_pods() {
    kubectl get pods -n default | awk '
    BEGIN {
        app1=0;
        app2=0;
        magenta="\033[1;35m";
        blue="\033[1;34m";
        reset="\033[0m";
    }
    NR==1 {
        print $0;
    }
    NR>1 {
        if ($1 ~ /blue/) {
            app1++;
            print blue $0 reset;
        } else if ($1 ~ /prpl/) {
            app2++;
            print magenta $0 reset;
        } else {
            print $0;
        }
    }
    END {
        print "\napp versions: " magenta app2 reset " / " blue app1 reset; 
    }
    '
}
export -f colorize_pods

function metrics_from_interceptor() {
    echo "KEDA metrics:"
    kubectl get --raw '/api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/queue' | \
        jq 'to_entries | map({key, value: ((.value.RPS | tostring) + " RPS")}) | from_entries'
}
export -f metrics_from_interceptor

function convert_to_ms() {
    time_str=$1
    min=$(echo $time_str | grep -oP '\d+(?=m)' | sed 's/^0*//')
    sec=$(echo $time_str | grep -oP '\d+.\d+(?=s)' | sed 's/^0*//')
    
    if [ -z "$min" ]; then
        min=0
    fi
    if [ -z "$sec" ]; then
        sec=0
    fi
    
    min_ms=$((min * 60000))
    sec_ms=$(echo "$sec * 1000" | bc)
    
    total_ms=$(echo "$min_ms + $sec_ms" | bc)
    total_ms=$(printf "%.0f" $total_ms)
    echo $total_ms
}
export -f convert_to_ms

function color() {
    elapsed_ms=$1
    if (( $(echo "$elapsed_ms > 100" | bc -l) )); then
        color="\033[0;31m"  # Red for over 100 milliseconds
    elif (( $(echo "$elapsed_ms >= 50" | bc -l) )); then
        color="\033[0;33m"  # Orange for over 50 milliseconds
    else
        color="\033[0;32m"  # Green for under 50 milliseconds
    fi
    echo $color
}
export -f color

function color_app() {
    if [[ "$#" -eq 0 ]]; then
        return
    fi
    app="${1}"
    if [[ "$app" == "[blue]" ]]; then
        color="\033[1;34m"
    else
        color="\033[1;35m"
    fi
    echo $color
}
export -f color_app

(
  echo "" > /tmp/hey.output
  echo "" >> /tmp/hey.output
  
  total_count_1=0
  total_count_2=0
  for run in $(seq 1 $NUMBER_OF_EXECUTIONS); do
    total_time=0
    count_1=0
    count_2=0
    echo "" > /tmp/hey.output
    echo "curl with ~10 req/sec, run $run/$NUMBER_OF_EXECUTIONS" >> /tmp/hey.output
    for i in {1..10}; do
      output=$( { time curl -s http://keda-meets-gw.com; } 2>&1 )
      curl_output=$(echo "$output" | head -n -3)
      elapsed_time=$(echo "$output" | grep real | awk '{print $2}')

      elapsed_ms=$(convert_to_ms "$elapsed_time")
      color="$(color $elapsed_ms)"
      color_app="$(color_app $curl_output)"
      
      printf "${color_app}%s ${color} %5sms\033[0m\n" "$curl_output" "$elapsed_ms" >> /tmp/hey.output
      
      total_time=$(echo "$total_time + $elapsed_ms" | bc)
      if [[ "$curl_output" == *"[blue]"* ]]; then
          count_1=$((count_1 + 1))
          total_count_1=$((total_count_1 + 1))
      elif [[ "$curl_output" == *"[prpl]"* ]]; then
          count_2=$((count_2 + 1))
          total_count_2=$((total_count_2 + 1))
      fi
    done
    average_time=$(echo "$total_time / 10" | bc)

    color="$(color $average_time)"
    printf "\nAverage time: ${color}%sms\033[0m\n" "$average_time" >> /tmp/hey.output
    printf "App versions: \033[1;35m%s\033[0m / \033[1;34m%s\033[0m\n" "$count_2" "$count_1" >> /tmp/hey.output
    if [[ "$NUMBER_OF_EXECUTIONS" -gt 1 ]]; then
      printf "Total app versions: \033[1;35m%s\033[0m / \033[1;34m%s\033[0m\n" "$total_count_2" "$total_count_1" >> /tmp/hey.output
    fi
    sleep 3
  done

  echo "" >> /tmp/hey.output
  echo "benchmark finished, press 'ctrl+c' to kill the watch loop" >> /tmp/hey.output
  echo "when you are done observing the application scale-in" >> /tmp/hey.output
)&
PID=$!

trap "kill $PID 2>/dev/null; kill -SIGKILL $(pidof watch) 2>/dev/null" EXIT
watch --no-title -n0.1 --color -x bash -c "colorize_pods; echo ''; metrics_from_interceptor; echo ''; cat /tmp/hey.output"
