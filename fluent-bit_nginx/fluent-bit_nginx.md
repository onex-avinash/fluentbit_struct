### NGINX - **172.16.101.80** 

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

2. Create the `fluent-bit.yml` in the folder `~/onextel/fluent-bit_nginx/config` :

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
/opt/fluent-bit/bin/fluent-bit -c ~/onextel/fluent-bit_nginx/config/fluent-bit.yml
```

4. `Ctrl+C` to exit the running service.

5. Create `log-paths.yml` file in the folder `~/onextel/fluent-bit_nginx/config` :

```yaml 
env:
  NGINX_LOG_PATH: ~/onextel/fluent-bit_nginx/logs/sbiuatapi.onex-aura.com.log
```

6. Create `parsers.conf` file in the folder `~/onextel/fluent-bit_nginx/config` :

```conf
[PARSER]
    Name   nginx
    Format regex
    Regex ^(?<remote_addr>[^ ]*) - (?<remote_user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+) (?:https?://[^/]+)?(?<path>/[^ \?]*?)/?(?:\?(?<params>[^\"]*?))? HTTP/[0-9.]*" (?<code>[^ ]*) (?<body_bytes_sent>[^ ]*) "(?<referer>[^\"]*)" "(?<agent>[^\"]*)" (?<request_time>[0-9.]*) (?<upstream_response_time>[0-9.]*) (?<pipe>[p\.])$
    Time_Key time
    Time_Format %d/%b/%Y:%H:%M:%S %z
```

9. Add the `lua` scripts in the folder `~/onextel/fluent-bit_nginx/lua` :

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

10. Edit the `fluent-bit.yml` that is created already in the folder `~/onextel/fluent-bit_nginx/config`

```yaml
includes:
  - /home/onexadmin/onextel/fluent-bit_nginx/config/log-paths.yml

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
  parsers_file: /home/onexadmin/onextel/fluent-bit_nginx/config/parsers.conf

pipeline:
  inputs:
    - name: tail
      path: ${NGINX_LOG_PATH}
      tag: nginx_logs
      path_key: server_name
      refresh_interval: ${REFRESH_INTERVAL}
      parser: nginx
      ignore_older: ${IGNORE_OLDER}

  filters:
    - name: lua
      match: nginx_logs
      script: /home/onexadmin/onextel/fluent-bit_nginx/lua/filter_invalid_record.lua
      call: filterinvalid_record

    - name: lua
      match: nginx_logs
      script: /home/onexadmin/onextel/fluent-bit_nginx/lua/extract_key.lua
      call: extract_key

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
ExecStart=/opt/fluent-bit/bin/fluent-bit -c /home/onexadmin/onextel/fluent-bit_nginx/config/fluent-bit.yml
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
