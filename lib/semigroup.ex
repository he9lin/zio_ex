defprotocol ZioEx.Semigroup do
  @doc "Combines two elements of the same type (Associative)."
  def combine(a, b)
end
