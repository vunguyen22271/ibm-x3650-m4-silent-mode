#!/bin/bash

# Get initial fan zone data
ipmi_output=$(ipmitool sdr 2>/dev/null)
fan_zones=($(echo "$ipmi_output" | grep 'Fan [0-9][A-Z] Tach' | awk -F'|' '{print $1}' | awk '{print $2}'))

echo "Detected fan zones: ${fan_zones[@]}"
echo "Number of fan zones: ${#fan_zones[@]}"

# Sleep interval between checks (in seconds)
SLEEP_INTERVAL=5

while true; do
  # Get current IPMI data
  ipmi_output=$(ipmitool sdr 2>/dev/null)
  
  # Extract CPU temperatures
  cpu_temps=($(echo "$ipmi_output" | grep 'CPU [0-9] Temp' | awk -F'|' '{print $2}' | awk '{print $1}'))

  echo "Current CPU temps: ${cpu_temps[@]}"

  # Find the maximum CPU temperature
  max=0
  for temp in "${cpu_temps[@]}"; do
    if (( temp > max )); then
      max=$temp
    fi
  done

  echo "Max CPU temp: ${max}°C"

  # Define temperature range
  min_temp=45  # Minimum temperature for fan control
  max_temp=80  # Maximum temperature for fan control

  # Calculate fan speed as a percentage (0-255 scale)
  if (( max <= min_temp )); then
    fan_speed=0
  elif (( max >= max_temp )); then
    fan_speed=255
  else
    # Linear scale between min_temp and max_temp
    fan_speed=$(( (max - min_temp) * 255 / (max_temp - min_temp) ))
  fi

  echo "Calculated fan speed (0-255 scale): $fan_speed"

  # Convert fan speed to hexadecimal
  fan_speed_hex=$(printf '%02x' $fan_speed)
  echo "Fan speed in hex: 0x$fan_speed_hex"

  # Set fan speed for each A zone (main fan zones)
  # Only control the 'A' fans (1A, 2A, 3A, 4A) as they are the primary fans
  # But only zones 1 and 2 seem to be controllable on this system
  zone_number=1
  for fan_zone in "${fan_zones[@]}"; do
    if [[ "$fan_zone" == *A ]]; then
      # Only try to control zones 1 and 2 (based on your system's capabilities)
      if [ $zone_number -le 2 ]; then
        echo "Setting fan zone $zone_number (Fan $fan_zone) to speed 0x$fan_speed_hex"
        
        # Format zone number as hex (01, 02)
        zone_hex=$(printf '%02x' $zone_number)
        
        # Execute IPMI command
        ipmitool raw 0x3a 0x07 0x$zone_hex 0x$fan_speed_hex 0x01
        
        if [ $? -eq 0 ]; then
          echo "Successfully set Fan Zone $zone_number"
        else
          echo "Failed to set Fan Zone $zone_number"
        fi
      else
        echo "Skipping fan zone $zone_number (Fan $fan_zone) - not controllable on this system"
      fi
      
      zone_number=$((zone_number + 1))
    fi
  done

  # Apply the changes
  echo "Applying fan speed changes..."
  ipmitool raw 0x3a 0x06
  
  if [ $? -eq 0 ]; then
    echo "Fan speed changes applied successfully"
  else
    echo "Failed to apply fan speed changes"
  fi

  echo "---"
  sleep $SLEEP_INTERVAL
done