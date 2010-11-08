$:.unshift File.join(BASE_DIR,'lib')
require 'filter'
$:.shift

SupFilters.filter_message message
