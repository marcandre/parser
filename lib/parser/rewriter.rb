module Parser

  ##
  # {Parser::Rewriter} offers a basic API that makes it easy to rewrite
  # existing ASTs. It's built on top of {Parser::AST::Processor} and
  # {Parser::Source::TreeRewriter} (or Parser::Source::Rewriter when
  # using the legacy API)
  #
  # For example, assume you want to remove `do` tokens from a while statement.
  # You can do this as following:
  #
  #     require 'parser/current'
  #
  #     class RemoveDo < Parser::Rewriter
  #       def on_while(node)
  #         # Check if the statement starts with "do"
  #         if node.location.begin.is?('do')
  #           remove(node.location.begin)
  #         end
  #       end
  #     end
  #
  #     code = <<-EOF
  #     while true do
  #       puts 'hello'
  #     end
  #     EOF
  #
  #     buffer        = Parser::Source::Buffer.new('(example)')
  #     buffer.source = code
  #     rewriter      = RemoveDo.new
  #
  #     # Rewrite the AST, returns a String with the new form.
  #     puts rewriter.rewrite(buffer)
  #
  # This would result in the following Ruby code:
  #
  #     while true
  #       puts 'hello'
  #     end
  #
  # Keep in mind that {Parser::Rewriter} does not take care of indentation when
  # inserting/replacing code so you'll have to do this yourself.
  #
  # See also [a blog entry](http://whitequark.org/blog/2013/04/26/lets-play-with-ruby-code/)
  # describing rewriters in greater detail.
  #
  # @api public
  #
  class Rewriter < Parser::AST::Processor
    ##
    # Rewrites the AST/source buffer and returns a String containing the new
    # version.
    #
    # @param [Parser::Source::Buffer] source_buffer
    # @param [Parser::AST::Node] ast (defaults to buffer parsed with CurrentRuby)
    # @param [Symbol] crossing_deletions:, different_replacements:, swallowed_insertions:
    #                 policy arguments for TreeRewriter (optional)
    # @return [String]
    #
    def rewrite(source_buffer,
                ast: Parser::CurrentRuby.new.parser(source_buffer),
                rewriting_class: Source::TreeRewriter,
                **policy)
      # We can't simply use `**policy` because of https://bugs.ruby-lang.org/issues/10856
      args = [policy] unless policy.empty?
      @source_rewriter = rewriting_class.new(source_buffer, *args)

      process(ast)

      @source_rewriter.process
    end

    module LegacyRewriter
      DEPRECATION_WARNING = [
        'Parser::Rewriter#rewrite(my_buffer, my_ast) uses the deprecated Parser::Source::Rewriter.',
        'Please use the new API Parser::Rewriter#rewrite(buffer, ast: ast) which',
        'uses Parser::Source::TreeRewriter instead'
      ].join("\n").freeze

      # This adds support for the legacy `rewrite(buffer, ast)`
      def rewrite(source_buffer, *args, **rest)
        return super if args.empty?
        raise ArgumentError, "wrong number of arguments (given 2, expected 1)" unless rest.empty?
        warn DEPRECATION_WARNING
        Source::Rewriter.warned_of_deprecation = true
        super(source_buffer, ast: args.first, rewriting_class: Source::Rewriter)
      end
    end
    prepend LegacyRewriter

    ##
    # Returns `true` if the specified node is an assignment node, returns false
    # otherwise.
    #
    # @param [Parser::AST::Node] node
    # @return [Boolean]
    #
    def assignment?(node)
      [:lvasgn, :ivasgn, :gvasgn, :cvasgn, :casgn].include?(node.type)
    end

    ##
    # Removes the source range.
    #
    # @param [Parser::Source::Range] range
    #
    def remove(range)
      @source_rewriter.remove(range)
    end

    ##
    # Wraps the given source range with the given values.
    #
    # @param [Parser::Source::Range] range
    # @param [String] content
    #
    def wrap(range, before, after)
      @source_rewriter.wrap(range, before, after)
    end

    ##
    # Inserts new code before the given source range.
    #
    # @param [Parser::Source::Range] range
    # @param [String] content
    #
    def insert_before(range, content)
      @source_rewriter.insert_before(range, content)
    end

    ##
    # Inserts new code after the given source range.
    #
    # @param [Parser::Source::Range] range
    # @param [String] content
    #
    def insert_after(range, content)
      @source_rewriter.insert_after(range, content)
    end

    ##
    # Replaces the code of the source range `range` with `content`.
    #
    # @param [Parser::Source::Range] range
    # @param [String] content
    #
    def replace(range, content)
      @source_rewriter.replace(range, content)
    end
  end

end
