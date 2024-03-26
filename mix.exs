defmodule Redi.MixProject do
  use Mix.Project

  @version "0.8.1"
  def project do
    [
      app: :redi,
      version: @version,
      elixir: "~> 1.15",
      package: package(),
      description: "An erlang ETS cache with TTL.",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        main: "Redi",
        source_ref: "v#{@version}",
        source_url: "https://github.com/bougueil/erlang-redi"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [extra_applications: [:logger]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :docs}
    ]
  end

  defp package do
    %{
      licenses: ["Apache-2.0"],
      maintainers: ["Renaud Mariana"],
      links: %{"GitHub" => "https://github.com/bougueil/erlang-redi"}
    }
  end
end
