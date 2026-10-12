# frozen_string_literal: true

require_relative '../contexts/messages'

module Proscenium
  module CLI
    # Every failure the CLI reports: a stable code, the exit status it maps to, and text that states
    # the problem, its cause and the fix. The text is Contexts::Messages', which the engine renders
    # too; golden-output tests pin the human text and the JSON event for each entry
    # (test/cli/golden/).
    class Error < StandardError
      EXIT = { success: 0, internal: 1, input: 2, unsupported: 3, drift: 4, integrity: 5,
               native: 6, busy: 7, interrupted: 8 }.freeze

      # code => the exit status it maps to.
      STATUS = {
        'PSM-E-USAGE' => :input,
        'PSM-E-GEMSPEC' => :input,
        'PSM-E-NOT-OPTED-IN' => :input,
        'PSM-E-FRONTEND-ROOT' => :input,
        'PSM-E-MANIFEST' => :input,
        'PSM-E-GEM-FILES' => :input,
        'PSM-E-NAME' => :input,
        'PSM-E-WORKSPACES' => :input,
        'PSM-E-HOOK' => :input,
        'PSM-E-SPEC' => :input,
        'PSM-E-CREDENTIAL' => :input,
        'PSM-E-ALIAS' => :input,
        'PSM-E-REACT' => :input,
        'PSM-E-CROSS-GEM' => :input,
        'PSM-E-NO-MANAGER' => :input,
        'PSM-E-MANAGER-CONFLICT' => :input,
        'PSM-E-UNSUPPORTED-MANAGER' => :unsupported,
        'PSM-E-BUN-LOCKB' => :unsupported,
        'PSM-E-MANAGER-MISSING' => :unsupported,
        'PSM-E-MANAGER-VERSION' => :unsupported,
        'PSM-E-EXPERIMENTAL-FROZEN' => :unsupported,
        'PSM-E-BUN-LINKER' => :unsupported,
        'PSM-E-NESTED-WORKSPACE' => :unsupported,
        'PSM-E-REGISTRATION' => :input,
        'PSM-E-REGISTRATION-EXCLUDED' => :input,
        'PSM-E-BUSY' => :busy,
        'PSM-E-NATIVE' => :native,
        'PSM-E-INTERRUPTED' => :interrupted,
        'PSM-E-CROSS-GEM-TARGET' => :input,
        'PSM-E-CONFIG' => :input,
        'PSM-E-PROBLEMS' => :input,
        'PSM-E-DRIFT' => :drift,
        'PSM-E-NOT-REGISTERED' => :drift,
        'PSM-E-GITIGNORE' => :drift,
        'PSM-E-LOCKFILE-MISSING' => :drift,
        'PSM-E-NOT-INSTALLED' => :drift,
        'PSM-E-REGISTRY-TARBALL' => :integrity,
        'PSM-E-WORKSPACE-MISSING' => :integrity,
        'PSM-E-PEER-SPLIT' => :integrity,
        'PSM-E-COLLISION' => :input,
        'PSM-E-BUN-DEFAULT-TRUSTED' => :unsupported,
        'PSM-E-TRUSTED-SOURCE' => :input,
        'PSM-E-PLATFORM-VARIANT' => :unsupported,
        'PSM-E-UNC-SHIM' => :unsupported,
        'PSM-E-OWNED-LINK' => :input,
        'PSM-E-OWNED-DIR' => :input,
        'PSM-W-END-OF-LIFE' => :success,
        'PSM-E-INTERNAL' => :internal
      }.freeze

      attr_reader :code, :fix, :details
      # What the package manager printed, for a native failure: not shown, only searched.
      attr_accessor :output

      # `escape`, when given, is the consumer's way around a gem author's problem, appended to the
      # fix.
      def initialize(code, details: {}, escape: nil, **args)
        @code = code
        @status = STATUS.fetch(code)
        @fix = [Contexts::Messages.fix(code, **args), escape].compact.join(' ')
        @details = details
        super(Contexts::Messages.message(code, **args))
      end

      def exit_status = EXIT.fetch(@status)
    end
  end
end
