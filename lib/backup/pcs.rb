require "backup"

Backup::Storage.autoload(:PCS, File.join(File.dirname(__FILE__), 'storage/pcs'))
