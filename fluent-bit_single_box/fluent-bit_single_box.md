### SINGLE VM - **172.16.101.64** 

>[!IMPORTANT]
>**Docker and Docker compose is not installed in it.** 
>It is required for Prometheus and Grafana installation
>

**TODO** : Docker Installation:

#### Installation steps:
1. Install Fluent-bit: 

```bash
curl https://packages.fluentbit.io/fluentbit.key | sudo gpg --dearmor -o /usr/share/keyrings/fluentbit-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/fluentbit-archive-keyring.gpg] https://packages.fluentbit.io/debian/bookworm bookworm main" | sudo tee /etc/apt/sources.list.d/fluentbit.list
sudo apt update
sudo apt install fluent-bit
```

2. Create the `fluent-bit.yml` in the folder `~/onextel/fluent-bit_single_box/config` :

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
/opt/fluent-bit/bin/fluent-bit -c ~/onextel/fluent-bit_single_box/config/fluent-bit.yml
```

4. `Ctrl+C` to exit the running service.

5. Create `log-paths.yml` file in the folder `~/onextel/fluent-bit_single_box/config` :

```yaml 
env:
  NGINX_LOG_PATH: ~/onextel/fluent-bit_single_box/logs/sbiuatapi.onex-aura.com.log
  DLR_LOG_PATH: ~/onextel/fluent-bit_single_box/logs/DlrSend_*.log
  DLVR_ERROR_CODE_LOG_PATH: ~/onextel/fluent-bit_single_box/logs/*_dlvr_error_code.log
```

6. Create `parsers.conf` file in the folder `~/onextel/fluent-bit_single_box/config` :

```conf
[PARSER]
    Name   nginx
    Format regex
    Regex ^(?<remote_addr>[^ ]*) - (?<remote_user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+) (?:https?://[^/]+)?(?<path>/[^ \?]*?)/?(?:\?(?<params>[^\"]*?))? HTTP/[0-9.]*" (?<code>[^ ]*) (?<body_bytes_sent>[^ ]*) "(?<referer>[^\"]*)" "(?<agent>[^\"]*)" (?<request_time>[0-9.]*) (?<upstream_response_time>[0-9.]*) (?<pipe>[p\.])$
    Time_Key time
    Time_Format %d/%b/%Y:%H:%M:%S %z

[PARSER]
    Name        json
    Format      json
    Time_Key    time
    Time_Format %Y-%m-%d %H:%M:%S

[PARSER]
    Name         dlvr_error
    Format       regex
    Regex        ^(?<time>\d{2}:\d{2}:\d{2}),(?<code>\d{3}),(?<porter_id>\d{4})$
    Time_Key     timestamp
    Time_Format  %d/%b/%Y:%H:%M:%S %z
```

9. Add the `lua` scripts in the folder `~/onextel/fluent-bit_single_box/lua` :

- `extract_key.lua` :
```lua
function extract_key(tag, timestamp, record)
    -- Debug print without cjson
    -- print("[DEBUG] Processing record with tag: " .. tostring(tag))

    -- Initialize api_key as no_key
    record.api_key = "no_key"
    
    if record.params then
        -- First try to find the key parameter
        local key = string.match(record.params, "key=([^&]*)")
        if key then
            record.api_key = key
            -- print("[DEBUG] Found API key: " .. tostring(key))
        else
            -- If key not found, try to find username
            local username = string.match(record.params, "username=([^&]*)")
            if username then
                record.api_key = username
                -- print("[DEBUG] Found username: " .. tostring(username))
            end
        end
    end

    -- If api_key is still "no_key", use remote_addr
    if record.api_key == "no_key" and record.remote_addr then
        record.api_key = record.remote_addr
        -- print("[DEBUG] Using remote_addr as key: " .. tostring(record.remote_addr))
    end
    
    -- Clean up params field
    record.params = nil
    
    -- Use virtual_server instead of filename since it's already set by record_modifier
    if record.server_name then
        -- Extract filename after last slash and remove .log extension
        record.server_name = record.server_name:match("[^/]+$"):gsub("%.log$", "")
        
        -- Debug print for extracted server_name
        -- print("[DEBUG] Updated server_name: " .. tostring(record.server_name))
    else
        -- print("[DEBUG] No server_name field found in record")
    end
    
    return 2, timestamp, record
end
```

- `filter_invalid_record.lua`
```lua
-- Define allowed paths globally
local ALLOWED_PATHS = {
    ["/sbi_send_sms"] = true,
    ["/"] = true
}

function filterinvalid_record(tag, timestamp, record)
    -- Print the incoming record
    -- print("[debug] Processing record:")
    for key, value in pairs(record) do
        -- print(string.format("[debug] %s: %s", key, value))
    end

    -- First check if parsing failed (raw log line)
    if record.log then
        print("[error] Parser failed for log line: " .. record.log)
        return -1, 0, 0
    end

    -- Validate path first (quick reject for unwanted paths)
    if not ALLOWED_PATHS[record.path] then
        print(string.format("[error] Invalid path: %s", record.path))
        return -1, 0, 0
    end

    -- Skip records from Monibot user agent
    if record.agent == "Monibot" then
        --print("Monibot found")
        return -1, 0, 0
    end

    -- Skip records with the path "/"
    if record.path == "/" then
        print("[info] Skipping record with path '/'")
        return -1, 0, 0
    end

    -- Define required fields and their expected types
    local required = {
        method = {"string", true},
        path = {"string", true},
        code = {"string", true},
        remote_addr = {"string", true},
        request_time = {"number", false},
        upstream_response_time = {"number", false}
    }
    
    -- Check for problems
    for field, config in pairs(required) do
        local expected_type, is_label = config[1], config[2]
        
        if record[field] == nil or record[field] == "" then
            print(string.format("[error] Missing or empty %s: %s", 
                              is_label and "label" or "field", field))
            return -1, 0, 0
        end
        
        if expected_type == "number" then
            local num = tonumber(record[field])
            if not num and record[field] ~= "-" then
                print(string.format("[error] Invalid numeric value for %s: %s", 
                                  field, record[field]))
                return -1, 0, 0
            end
        end
    end
    
    return 2, timestamp, record
end
```


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


- `extract_dlvr_error_code.lua` :
```lua
function extract_dlvr_error_code(tag, timestamp, record)
    -- Define the fields to extract based on the parser
    local required_fields = {
        time = "time",
        code = "code",
        porter_id = "porter_id"
    }

    -- Validate and ensure all required fields are present in the record
    for field, source in pairs(required_fields) do
        if not record[source] then
            print(string.format("[error] Missing field '%s' in record", source))
            return -1, 0, 0
        end
    end

    -- Assign the required fields directly to the record
    record.time = record.time
    record.code = record.code
    record.porter_id = record.porter_id

    -- Debugging: Print the updated record
    -- print(string.format("[info] Updated Record: time=%s, code=%s, porter_id=%s",
    --     record.time, record.code, record.porter_id))

    -- Return the updated record
    return 2, timestamp, record
end
```



10. Edit the `fluent-bit.yml` that is created already in the folder `~/onextel/fluent-bit_single_box/config`

```yaml
includes:
  - /home/onexadmin/onextel/fluent-bit_single_box/config/log-paths.yml

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
  parsers_file: /home/onexadmin/onextel/fluent-bit_single_box/config/parsers.conf

pipeline:
  inputs:
    - name: tail
      path: ${NGINX_LOG_PATH}
      tag: nginx_logs
      path_key: server_name
      refresh_interval: ${REFRESH_INTERVAL}
      parser: nginx
      ignore_older: ${IGNORE_OLDER}

    - name: tail
      path: ${DLR_LOG_PATH}
      tag: dlr_logs
      parser: json
      refresh_interval: ${REFRESH_INTERVAL}
      ignore_older: ${IGNORE_OLDER}

    - name: tail
      path: ${DLVR_ERROR_CODE_LOG_PATH}
      tag: dlvr_error_code_logs
      refresh_interval: ${REFRESH_INTERVAL}
      parser: dlvr_error
      ignore_older: ${IGNORE_OLDER}

  filters:
    - name: lua
      match: nginx_logs
      script: /home/onexadmin/onextel/fluent-bit_single_box/lua/filter_invalid_record.lua
      call: filterinvalid_record

    - name: lua
      match: nginx_logs
      script: /home/onexadmin/onextel/fluent-bit_single_box/lua/extract_key.lua
      call: extract_key

    - name: lua
      match: dlr_logs
      script: /home/onexadmin/onextel/fluent-bit_single_box/lua/process_dlr.lua
      call: process_dlr

    - name: lua
      match: dlvr_error_code_logs
      script: /home/onexadmin/onextel/fluent-bit_single_box/lua/extract_dlvr_error_code.lua
      call: extract_dlvr_error_code

    - name: log_to_metrics
      match: nginx_logs
      tag: nginx_metrics
      metric_mode: counter
      metric_name: requests_total
      metric_description: Total number of HTTP requests
      label_field:
        - code
        - method
        - path
        - api_key
      flush_interval_sec: ${METRICS_FLUSH_INTERVAL}
      flush_interval_nsec: 0

    - name: log_to_metrics
      match: nginx_logs
      tag: nginx_metrics
      metric_mode: histogram
      metric_name: request_duration_seconds
      metric_description: Distribution of request processing times
      value_field: request_time
      label_field:
        - code
        - method
        - path
        - api_key
      bucket:
        - 0.1
        - 0.5
        - 1.0
        - 3.0
        - 5.0
      flush_interval_sec: 15

    - name: log_to_metrics
      match: nginx_logs
      tag: nginx_metrics
      metric_mode: histogram
      metric_name: upstream_duration_seconds
      metric_description: Distribution of upstream response times
      value_field: upstream_response_time
      label_field:
        - code
        - method
        - path
        - api_key
      bucket:
        - 0.1
        - 0.5
        - 1.0
        - 3.0
        - 5.0
      flush_interval_sec: 15

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

    - name: log_to_metrics
      match: dlvr_error_code_logs
      tag: dlvr_error_code_metrics
      metric_mode: counter
      metric_name: total_dlvr_error_code
      metric_description: Total number of DLR error codes
      label_field:
        - porter_id
        - code
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
ExecStart=/opt/fluent-bit/bin/fluent-bit -c /home/onexadmin/onextel/fluent-bit_single_box/config/fluent-bit.yml
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
User=onexadmin
Group=onexadmin

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
