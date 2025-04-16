### API - **172.16.101.73** 

#### Installation steps:
1. Install Fluent-bit: 

```bash
curl https://packages.fluentbit.io/fluentbit.key | sudo gpg --dearmor -o /usr/share/keyrings/fluentbit-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/fluentbit-archive-keyring.gpg] https://packages.fluentbit.io/debian/bookworm bookworm main" | sudo tee /etc/apt/sources.list.d/fluentbit.list
sudo apt update
sudo apt install fluent-bit
```

2. Create the `fluent-bit.yml` in the folder `~/onextel/fluent-bit_api/config` :

```yaml
service:
  flush: 1
  daemon: Off
  log_level: info
  parsers_file: parsers.conf
  plugins_file: plugins.conf
  http_server: Off
  http_listen: 0.0.0.0
  http_port: 2020
  storage_metrics: on

pipeline:
  inputs:
    - name: cpu
      tag: cpu.local
      interval_sec: 1
  
  outputs:
    - name: stdout
      match: "*"
```

3. Check if the config file is working correctly by executing: 

```bash
/opt/fluent-bit/bin/fluent-bit -c ~/onextel/fluent-bit_api/config/fluent-bit.yml
```

4. `Ctrl+C` to exit the running service.

5. Create `log-paths.yml` file in the folder `~/onextel/fluent-bit_api/config` :

```yaml
env:
  DLR_LOG_PATH: ~/onextel/fluent-bit_api/logs/DlrSend_*.log
```

6. Create `parsers.conf` file in the folder `~/onextel/fluent-bit_api/config` :

```conf
[PARSER]
    Name        json
    Format      json
    Time_Key    time
    Time_Format %Y-%m-%d %H:%M:%S
```

9. Add the `lua` scripts in the folder `~/onextel/fluent-bit_api/lua` :

- `process_dlr.lua` : 
```lua
function process_dlr(tag, timestamp, record)
  -- print("[DEBUG] process_dlr called with tag: " .. tostring(tag))
  -- print("[DEBUG] Available fields:")
  -- for k, v in pairs(record) do
  --    print("  " .. tostring(k) .. ": " .. tostring(v))
  -- end

  -- Calculate response time in milliseconds
  if record.submit_ts and record.acked_ts then
      record.response_time = (record.acked_ts - record.submit_ts) / 1000.0  -- Convert to seconds
    --  print("[DEBUG] Calculated response time: " .. tostring(record.response_time) .. " seconds")
    --  print("[DEBUG] Using acked_ts: " .. tostring(record.acked_ts))
    --  print("[DEBUG] Using submit_ts: " .. tostring(record.submit_ts))
  else
      record.response_time = 0
      -- print("[DEBUG] Could not calculate response time - missing timestamps")
      -- print("[DEBUG] submit_ts: " .. tostring(record.submit_ts))
      -- print("[DEBUG] acked_ts: " .. tostring(record.acked_ts))
  end
  
  -- Ensure all required fields exist
  record.api_key = record.api_key or "unknown"
  record.http_resp = record.http_resp or 0
  
  -- Extract base URL without query parameters
  if record.url then
      record.url = string.match(record.url, "([^?]+)") or record.url
  else
      record.url = "unknown"
  end
  
  -- print("[DEBUG] Processed record - response_time: " .. tostring(record.response_time))
  return 2, timestamp, record
end
```


10. Edit the `fluent-bit.yml` that is created already in the folder `~/onextel/fluent-bit_api/config`

```yaml
includes:
  - /home/onexadmin/onextel/fluent-bit_api/config/log-paths.yml

env:
  FLUSH_INTERVAL: 15
  LOG_LEVEL: info
  PROMETHEUS_HOST: 0.0.0.0
  PROMETHEUS_PORT: 2020
  REFRESH_INTERVAL: 10
  IGNORE_OLDER: 1d
  METRICS_FLUSH_INTERVAL: 15

service:
  flush: ${FLUSH_INTERVAL}
  log_level: ${LOG_LEVEL}
  parsers_file: /home/onexadmin/onextel/fluent-bit_api/config/parsers.conf

pipeline:
  inputs:
    - name: tail
      path: ${DLR_LOG_PATH}
      tag: dlr_logs
      parser: json
      refresh_interval: ${REFRESH_INTERVAL}
      ignore_older: ${IGNORE_OLDER}

  filters:
    - name: lua
      match: dlr_logs
      script: /home/onexadmin/onextel/fluent-bit_api/lua/process_dlr.lua
      call: process_dlr

    - name: log_to_metrics
      match: dlr_logs
      tag: dlr_metrics
      metric_mode: counter
      metric_name: total_dlr_send
      metric_description: Total number of DLR sends
      label_field:
        - api_key
        - http_resp
        - url
      flush_interval_sec: 15

    - name: log_to_metrics
      match: dlr_logs
      tag: dlr_metrics
      metric_mode: histogram
      metric_name: dlr_response_time_seconds
      metric_description: Distribution of DLR response times
      value_field: response_time
      label_field:
        - api_key
        - http_resp
        - url
      bucket:
        - 0.1
        - 0.5
        - 1.0
        - 3.0
        - 5.0
      flush_interval_sec: 15

  outputs:
    - name: prometheus_exporter
      match: "*_metrics"
      host: ${PROMETHEUS_HOST}
      port: ${PROMETHEUS_PORT}
```


#### Run the fluent-bit as a system service
- Check the availability of the port: 
```bash
sudo lsof -i :2020
```

- Edit the file `fluent-bit.service` file:
```bash
sudo tee /etc/systemd/system/fluent-bit.service > /dev/null <<EOF
[Unit]
Description=Fluent Bit Service
After=network.target

[Service]
ExecStart=/opt/fluent-bit/bin/fluent-bit -c /home/onexadmin/onextel/fluent-bit_api/config/fluent-bit.yml
Restart=on-failure
StandardOutput=journal
StandardError=journal
User=fluent
Group=fluent

[Install]
WantedBy=multi-user.target
EOF
```

>[!IMPORTANT]
>The User and Group might give error in the Virtual Machine or Server sometime due to restricted access to user only. 
>Try using the user of the VM (here: `onexadmin`) 
>```bash
> User=onexadmin
> Group=onexadmin
>```

- Create the user:
```bash
sudo useradd --system --no-create-home --shell /sbin/nologin fluent
sudo chown -R fluent:fluent /etc/fluent-bit
```

- Start the service:
```bash
sudo systemctl start fluent-bit.service
```

- Enable the service:
```bash
sudo systemctl enable fluent-bit.service
```

- Check the status: 
```bash
sudo systemctl status fluent-bit.service
```
