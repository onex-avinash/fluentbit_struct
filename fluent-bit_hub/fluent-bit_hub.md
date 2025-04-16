### HUB - **172.16.101.64** 

#### Installation steps:
1. Install Fluent-bit: 

```bash
curl https://packages.fluentbit.io/fluentbit.key | sudo gpg --dearmor -o /usr/share/keyrings/fluentbit-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/fluentbit-archive-keyring.gpg] https://packages.fluentbit.io/debian/bookworm bookworm main" | sudo tee /etc/apt/sources.list.d/fluentbit.list
sudo apt update
sudo apt install fluent-bit
```

2. Create the `fluent-bit.yml` in the folder `~/onextel/fluent-bit_hub/config` :

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
/opt/fluent-bit/bin/fluent-bit -c ~/onextel/fluent-bit_hub/config/fluent-bit.yml
```

4. `Ctrl+C` to exit the running service.

5. Create `log-paths.yml` file in the folder `~/onextel/fluent-bit_hub/config` :

```yaml
env:
  DLVR_ERROR_CODE_LOG_PATH: ~/onextel/fluent-bit_hub/logs/*_dlvr_error_code.log
```

6. Create `parsers.conf` file in the folder `~/onextel/fluent-bit_hub/config` :

```conf
[PARSER]
    Name         dlvr_error
    Format       regex
    Regex        ^(?<time>\d{2}:\d{2}:\d{2}),(?<code>\d{3}),(?<porter_id>\d{4})$
    Time_Key     timestamp
    Time_Format  %d/%b/%Y:%H:%M:%S %z
```

9. Add the `lua` scripts in the folder `~/onextel/fluent-bit_hub/lua` :

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

10. Edit the `fluent-bit.yml` that is created already in the folder `~/onextel/fluent-bit_hub/config`

```yaml
includes:
  - /home/onexadmin/onextel/fluent-bit_hub/config/log-paths.yml

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
  parsers_file: /home/onexadmin/onextel/fluent-bit_hub/config/parsers.conf

pipeline:
  inputs:
    - name: tail
      path: ${DLVR_ERROR_CODE_LOG_PATH}
      tag: dlvr_error_code_logs
      refresh_interval: ${REFRESH_INTERVAL}
      parser: dlvr_error
      ignore_older: ${IGNORE_OLDER}

  filters:
    - name: lua
      match: dlvr_error_code_logs
      script: /home/onexadmin/onextel/fluent-bit_hub/lua/extract_dlvr_error_code.lua
      call: extract_dlvr_error_code

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
ExecStart=/opt/fluent-bit/bin/fluent-bit -c /home/onexadmin/onextel/fluent-bit_hub/config/fluent-bit.yml
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
