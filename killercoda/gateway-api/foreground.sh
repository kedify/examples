while read -r line; do
  echo "$line"
  if [[ $line == "-- ready" ]]; then
      exit 0
  fi
done < <(tail -f /tmp/progress)
