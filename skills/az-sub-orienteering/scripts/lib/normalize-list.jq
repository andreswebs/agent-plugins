# Unwrap {value: [...]} (older az builds) or {data: [...]} into a bare array.
if type == "array" then .
elif type == "object" then (.value // .data // [])
else []
end
