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
--   print(string.format("[info] Updated Record: time=%s, code=%s, porter_id=%s",
--       record.time, record.code, record.porter_id))

  -- Return the updated record
  return 2, timestamp, record
end