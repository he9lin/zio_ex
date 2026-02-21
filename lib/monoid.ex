defprotocol ZioEx.Monoid do
  # A Monoid is just a Semigroup that also has an identity
  @doc "Returns the identity element for the type."
  def empty(sample)
end
