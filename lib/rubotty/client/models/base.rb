# frozen_string_literal: true

module Rubotty
  class Client
    # Every typed response this client hands back lives under here, one class
    # per shape the API documents, built from the same Hash {Transport}
    # already decoded rather than changing how bytes become Ruby data.
    module Models
      # The machinery every model in this namespace is built from: a
      # declared field list, a real accessor per field, and a `from_h` that
      # pulls each one out of the decoded Hash by its own string key. Nothing
      # here is generated from the OpenAPI document at load time; the field
      # lists are written by hand against it once, so a typo shows up as a
      # silently nil attribute rather than as a class this gem forgot to ship.
      #
      # `fields` accumulates across a subclass rather than replacing the
      # parent's list, which is what lets `RoomFeature < Feature` add just its
      # own `inherited` field and still expose every field `Feature` declared.
      class Base
        class << self
          attr_reader :field_names

          # @param names [Array<Symbol>] every field this model exposes, in
          #   the order they read best, not the order the API happens to list
          #   them
          # @param readonly [Array<Symbol>] the subset the API assigns, an id
          #   foremost among them, where a setter would let a caller believe
          #   changing it locally changes the record it came from. These get
          #   `attr_reader` instead of `attr_accessor`.
          def fields(*names, readonly: [])
            @field_names = inherited_field_names + names
            @casts = inherited_casts.dup
            @remainder_field = superclass.respond_to?(:remainder_field) ? superclass.remainder_field : nil
            attr_accessor(*(names - Array(readonly)))
            attr_reader(*Array(readonly))
          end

          # Declare how one field's raw value becomes something other than
          # the scalar it decoded as: another model, an array of them. A
          # field named here with no cast is handed to the accessor exactly
          # as YAML decoded it, which is right for every plain scalar and for
          # a field that is genuinely a free-form Hash the API leaves open,
          # a feature's config among them.
          def cast(name, caster) = casts[name] = caster

          def casts = @casts ||= {}

          # Every field this model does not declare lands here instead of
          # being dropped, keyed exactly as the API sent it. Only worth
          # naming on a shape the API itself documents as open-ended (an
          # analytics window's per-category breakdown, a process report's
          # forward-compatible extras), where flattening every possible key
          # into its own accessor would describe today's release rather than
          # whichever one a caller is actually talking to.
          attr_reader :remainder_field

          def remainder(name)
            @remainder_field = name
            attr_accessor name
          end

          # Build one instance from a decoded Hash. `nil` in, `nil` out, so a
          # nullable field nests without every call site needing its own
          # guard first.
          def from_h(hash)
            return nil if hash.nil?

            instance = allocate
            field_names.each do |name|
              raw = hash[name.to_s]
              caster = casts[name]
              instance.instance_variable_set(:"@#{name}", caster ? caster.call(raw) : raw)
            end
            if remainder_field
              covered = field_names.map(&:to_s)
              instance.instance_variable_set(:"@#{remainder_field}", hash.reject { |k, _| covered.include?(k) })
            end
            instance
          end

          # Cast a list route's answer, or one field nesting an array of this
          # model, into an `Array` of real instances. `nil` reads as no rows
          # rather than raising, since a nullable array field is nil exactly
          # when the API considered it absent, and an empty list already
          # means the same thing an absent one would.
          def array(hash_or_nil) = Array(hash_or_nil).map { |row| from_h(row) }

          private

          def inherited_field_names
            superclass.respond_to?(:field_names) ? Array(superclass.field_names) : []
          end

          def inherited_casts
            superclass.respond_to?(:casts) ? superclass.casts : {}
          end
        end
      end
    end
  end
end
