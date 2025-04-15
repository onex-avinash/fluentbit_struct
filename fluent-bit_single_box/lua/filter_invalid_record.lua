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