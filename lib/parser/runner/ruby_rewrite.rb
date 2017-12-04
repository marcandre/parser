require 'parser/runner'
require 'tempfile'

module Parser

  class Runner::RubyRewrite < Runner
    def initialize
      super

      @rewriters = []
      @modify    = false
      @check_against_tree = true
      @rewriting_class = Source::Rewriter
    end

    private

    def runner_name
      'ruby-rewrite'
    end

    def setup_option_parsing(opts)
      super(opts)

      opts.on '-l file', '--load', 'Load a rewriter' do |file|
        load_and_discover(file)
      end

      opts.on '-m', '--modify', 'Assume rewriters normally modify AST' do
        @modify = true
      end

      opts.on '-w', '--rewriter TYPE', %i[legacy tree compat], 'Use rewriter [tree|legacy|compat]' do |rewriter|
        case rewriter
        when :legacy
          @check_against_tree = false
        when :tree
          @check_against_tree = false
          @rewriting_class = Source::TreeRewriter
        end
      end
    end

    def load_and_discover(file)
      load file

      const_name = File.basename(file).
        sub(/\.rb$/, '').
        gsub(/(^|_)([a-z])/) do |m|
          "#{$2.upcase}"
        end

      @rewriters << Object.const_get(const_name)
    end

    def process(initial_buffer)
      Source::Rewriter.warned_of_deprecation = true if @check_against_tree

      buffer = initial_buffer
      original_name = buffer.name

      @rewriters.each do |rewriter_class|
        @parser.reset
        ast = @parser.parse(buffer)

        rewriter = rewriter_class.new
        new_source = rewriter.rewrite(buffer, ast: ast, rewriting_class: @rewriting_class)
        if @check_against_tree
          prev, $stderr = $stderr, File.open(File::NULL, "w")
          begin
            check = rewriter.rewrite(buffer, ast: ast, rewriting_class: Source::TreeRewriter)
          rescue ClobberingError
            # Nothing to else do, since check won't match new_source
          ensure
            $stderr = prev
          end
          self.class.warn_of_deprecation if check != new_source
        end

        new_buffer = Source::Buffer.new(initial_buffer.name +
                                    '|after ' + rewriter_class.name)
        new_buffer.source = new_source

        @parser.reset
        new_ast = @parser.parse(new_buffer)

        if !@modify && ast != new_ast
          $stderr.puts 'ASTs do not match:'

          old = Tempfile.new('old')
          old.write ast.inspect + "\n"; old.flush

          new = Tempfile.new('new')
          new.write new_ast.inspect + "\n"; new.flush

          IO.popen("diff -u #{old.path} #{new.path}") do |io|
            diff = io.read.
              sub(/^---.*/,    "--- #{buffer.name}").
              sub(/^\+\+\+.*/, "+++ #{new_buffer.name}")

            $stderr.write diff
          end

          exit 1
        end

        buffer = new_buffer
      end

      if File.exist?(original_name)
        File.open(original_name, 'w') do |file|
          file.write buffer.source
        end
      else
        if input_size > 1
          puts "Rewritten content of #{buffer.name}:"
        end

        puts buffer.source
      end
    end

    DEPRECATION_WARNING = [
      'The outputs differ when using the deprecated legacy rewriter and the tree rewriter.',
      'Please make sure your code works with the tree rewriter and use ruby-rewrite with',
      'the `--rewriter=tree` option.',
    ].join("\n").freeze

    extend Deprecation
  end

end
