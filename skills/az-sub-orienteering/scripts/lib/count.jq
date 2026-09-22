# Number of items in an az list result: bare array, {value: [...]} wrapper, or
# a single object (counts as 1).
if type == "array" then length
elif type == "object" then
    (if has("value") and (.value | type == "array") then (.value | length) else 1 end)
else 0
end
