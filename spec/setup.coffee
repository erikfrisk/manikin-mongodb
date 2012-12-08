path = require('path')

exports.requireSource = (file) ->
  require(path.join(__dirname, '..', process.env.SRC_DIR || 'lib', file))
