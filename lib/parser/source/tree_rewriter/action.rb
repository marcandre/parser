# frozen_string_literal: true

module Parser
  module Source
    ##
    # @api private
    #
    # Actions are arranged in a tree and get combined so that:
    #   children are strictly contained by their parent
    #   sibblings all disjoint from one another
    #   only actions with replacement==nil may have children
    #
    class TreeRewriter::Action
      attr_reader :range, :replacement, :insert_before, :insert_after

      def initialize(range, enforcer,
           insert_before: '',
           replacement: nil,
           insert_after: '',
           children: []
        )
        @range, @enforcer, @children, @insert_before, @replacement, @insert_after =
          range, enforcer, children.freeze, insert_before.freeze, replacement, insert_after.freeze

        freeze
      end

      def combine(action)
        return self if action.empty? # Ignore empty action
        do_combine(action)
      end

      def empty?
        @insert_before.empty? &&
          @insert_after.empty? &&
          @children.empty? &&
          (@replacement == nil || (@replacement.empty? && @range.empty?))
      end

      def ordered_replacements
        reps = []
        reps << [@range.begin, @insert_before] unless @insert_before.empty?
        reps << [@range, @replacement] if @replacement
        reps.concat(@children.sort_by(&:range).flat_map(&:ordered_replacements))
        reps << [@range.end, @insert_after] unless @insert_after.empty?
        reps
      end

      def insertion?
        !insert_before.empty? || !insert_after.empty? || (replacement && !replacement.empty?)
      end

      protected

      attr_reader :children

      def with(range: @range, enforcer: @enforcer, children: @children, insert_before: @insert_before, replacement: @replacement, insert_after: @insert_after)
        children = swallow(children) if replacement
        self.class.new(range, enforcer, children: children, insert_before: insert_before, replacement: replacement, insert_after: insert_after)
      end

      # Assumes range.contains?(action.range) && action.children.empty?
      def do_combine(action)
        if action.range == @range
          merge(action)
        else
          place_in_hierarchy(action)
        end
      end

      def place_in_hierarchy(action)
        family = analyse_hierarchy(action)

        if family[:fusible]
          fuse_deletions(action, family[:fusible], [*family[:sibbling], *family[:child]])
        else
          extra_sibbling = if family[:parent]  # action should be a descendant of one of the children
            family[:parent][0].do_combine(action)
          elsif family[:child]                 # or it should become the parent of some of the children,
            action.with(children: family[:child], enforcer: @enforcer)
              .combine_children(action.children)
          else                                 # or else it should become an additional child
            action
          end
          with(children: [*family[:sibbling], extra_sibbling])
        end
      end

      # Assumes more_children all contained within @range
      def combine_children(more_children)
        more_children.inject(self) do |parent, new_child|
          parent.place_in_hierarchy(new_child)
        end
      end

      def fuse_deletions(action, fusible, other_sibblings)
        without_fusible = with(children: other_sibblings)
        fused_range = [action, *fusible].map(&:range).inject(:join)
        fused_deletion = action.with(range: fused_range)
        without_fusible.do_combine(fused_deletion)
      end

      def analyse_hierarchy(action)
        @children.group_by { |child| child.relationship_with(action) }
      end

      # Returns what relationship self should have with `action`; either of
      #   :sibbling, :parent, :child, :fusible or raises a CloberingError
      # In case of equal range, returns :parent
      def relationship_with(action)
        if action.range == @range || @range.contains?(action.range)
          :parent
        elsif @range.contained?(action.range)
          :child
        elsif @range.disjoint?(action.range)
          :sibbling
        elsif !action.insertion? && !insertion?
          @enforcer.call(:crossing_deletions) { {range: action.range, conflict: @range} }
          :fusible
        else
          @enforcer.call(:crossing_insertions) { {range: action.range, conflict: @range} }
        end
      end

      # Assumes action.range == range && action.children.empty?
      def merge(action)
        call_enforcer_for_merge(action)
        with(
          insert_before: "#{action.insert_before}#{insert_before}",
          replacement: action.replacement || @replacement,
          insert_after: "#{insert_after}#{action.insert_after}",
        ).combine_children(action.children)
      end

      def call_enforcer_for_merge(action)
        @enforcer.call(:different_replacements) do
          if @replacement && action.replacement && @replacement != action.replacement
            {range: @range, replacement: action.replacement, other_replacement: @replacement}
          end
        end
      end

      def swallow(children)
        @enforcer.call(:swallowed_insertions) do
          insertions = children.select(&:insertion?)

          {range: @range, conflict: insertions.map(&:range)} unless insertions.empty?
        end
        []
      end
    end
  end
end
