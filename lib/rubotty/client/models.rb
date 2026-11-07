# frozen_string_literal: true

# One file per family of shapes, {Rubotty::Client::Models::Base} first since
# every other file subclasses it. Past that, load order does not matter: a
# cast between families (an onboarding decision naming a Community, a
# {Rubotty::Client::Models::ProcessInfo} naming a ScriptingInfo) is a Proc
# that resolves the other class by constant lookup when a response actually
# needs building, not while these files are loading.
require_relative "models/base"
require_relative "models/communities"
require_relative "models/rooms"
require_relative "models/messaging"
require_relative "models/bridge"
require_relative "models/people"
require_relative "models/viewers"
require_relative "models/features"
require_relative "models/faq_join_links"
require_relative "models/platform_wiring"
require_relative "models/guests_events"
require_relative "models/onboarding"
require_relative "models/alerts"
require_relative "models/participation"
require_relative "models/admin"
require_relative "models/scripts"
require_relative "models/debug"
require_relative "models/webhooks"
require_relative "models/backfill"
require_relative "models/files"
