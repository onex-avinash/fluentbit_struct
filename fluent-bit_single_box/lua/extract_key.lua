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