class Rewriter < Parser::Rewriter
  def on_send(node)
    @source_rewriter.insert_before_multi(node.loc.expression, '1')
    @source_rewriter.insert_after_multi(node.loc.expression, '2')
    @source_rewriter.insert_before_multi(node.children[0].loc.expression, '3')
    @source_rewriter.insert_after_multi(node.children[0].loc.expression, '4')
    super
  end
end
