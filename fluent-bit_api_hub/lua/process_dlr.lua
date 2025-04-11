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