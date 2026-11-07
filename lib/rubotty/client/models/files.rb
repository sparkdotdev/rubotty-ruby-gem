# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # A file the deployment is holding. Carries no UUID and no download
      # link, since neither is recoverable from what is stored; see
      # {FileRecordWithLink} for the two calls that mint one.
      #
      # Named FileRecord rather than File so it never shadows ::File, which
      # {Client#admin_upload_file} still uses to open a path.
      class FileRecord < Base
        fields :id, :filename, :content_type, :byte_size, :sealed_bytes, :room_key, :source, :created_by,
               :created_at, :expires_at, readonly: %i[id byte_size sealed_bytes]
      end

      # What an upload, a rotation or an expiry answers with: everything
      # {FileRecord} has, plus the UUID naming the file and the download
      # link built from it. The UUID is not stored and cannot be asked for
      # again once it is lost.
      class FileRecordWithLink < FileRecord
        fields :uuid, :url, readonly: %i[uuid url]
      end
    end
  end
end
