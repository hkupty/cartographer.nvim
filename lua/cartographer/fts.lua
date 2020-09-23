local fts = {}

-- replace with treesitter later on..
fts.lua = {
  functions = "function"
}

fts.clojure = {
  functions = "(de)?fn"
}

fts.python = {
  functions = "(def|lambda)"
}


return fts
