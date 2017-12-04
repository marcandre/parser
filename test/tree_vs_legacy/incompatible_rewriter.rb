class IncompatibleRewriter < Parser::Rewriter
  def on_send(node)
    @source_rewriter.insert_before(node.loc.expression, '1')
    @source_rewriter.insert_before(node.loc.expression.adjust(begin_pos: 1, end_pos: 1), '1')
    super
  end
end
