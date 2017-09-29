defmodule LolBuddy.Players.Matching do
  alias LolBuddy.Players.Player
  alias LolBuddy.Players.Criteria
  # resource for who can play with who
  # https://support.riotgames.com/hc/en-us/articles/204010760-Ranked-Play-FAQ

  @doc """
  Returns a boolean representing whether Player 'player' and Player 'candidate'
  are able to play together and fit eachother's criteria.

  ## Examples
      iex> diamond1 = %{type: "RANKED_SOLO_5x5", tier: "DIAMOND", rank: 1}
      iex> criteria1 = %Criteria{positions: [:top, :support], voice: false, age_groups: [1]}
      iex> criteria2 = %Criteria{positions: [:marksman, :top], voice: false, age_groups: [1]}
      iex> player = %Player{id: 1, name: "Lethly", region: :euw, voice: false,
        languages: ["danish"], age_group: 1, positions: [:marksman],
        leagues: [diamond1], champions: ["Vayne", "Caitlyn", "Ezreal"], 
        criteria: criteria1}
      iex> candidate = %Player{id: 2, name: "hansp", region: :euw, voice: false,
        languages: ["danish", "english"], age_group: 1, positions: [:top],
        leagues: [diamond1], champions: ["Cho'Gath", "Renekton", "Riven"], 
        criteria: criteria2}
      iex> LolBuddy.Players.Matching.match?(player, candidate)
      true
  """
  def match?(%Player{} = player, %Player{} = candidate) do
    player.id != candidate.id
    && can_queue?(player, candidate)
    && lists_intersect?(player.languages, candidate.languages)
    && criteria_compatible?(player.criteria, candidate) 
    && criteria_compatible?(candidate.criteria, player)
  end

  # convert two lists to MapSets and see if they intersect?
  defp lists_intersect?(a, b) do
    MapSet.intersection(MapSet.new(a), MapSet.new(b)) != []
  end

  # helper for extracting solo queue and determining if it is possible for
  # two players to queue together
  defp can_queue?(%Player{} = player, %Player{} = candidate) do
    case player.region == candidate.region do
      false -> false
      _     -> is_solo? = &(&1.type == "RANKED_SOLO_5x5")
               player_solo = Enum.find(player.leagues, is_solo?)
               candidate_solo = Enum.find(candidate.leagues, is_solo?)
               tier_compatible?(player_solo, candidate_solo)
    end
  end

  @doc """
  Returns a boolean representing whether the Player 'player'
  conforms to the Criteria 'criteria'

  ## Examples
      iex> diamond1 = %{type: "RANKED_SOLO_5x5", tier: "DIAMOND", rank: 1}
      iex> criteria = %Criteria{positions: [:marksman], voice: false, age_groups: [1]}
      iex> player = %Player{id: 1, name: "Lethly", region: :euw, voice: false,
        languages: ["danish"], age_group: 1, positions: [:marksman],
        leagues: [diamond1], champions: ["Vayne", "Caitlyn", "Ezreal"], 
        criteria: criteria}
      iex> LolBuddy.Players.Matching.criteria_compatible?(criteria, player)
      true
  """
  def criteria_compatible?(%Criteria{} = criteria, %Player{} = player) do
      criteria.voice == player.voice
      && lists_intersect?(criteria.positions, player.positions) 
      && Enum.member?(criteria.age_groups, player.age_group)
  end

  # Defined according to below
  # https://support.riotgames.com/hc/en-us/articles/204010760-Ranked-Play-FAQ
  # Helper for handling special restrictions for cases
  # when the players queuing have a tier discrepancy of 1
  defp rank_compatible?(%{tier: ht, rank: hr}, %{tier: lt, rank: lr}) do
    loose_tiers = ["BRONZE", "SILVER", "GOLD", "PLATINUM"]
    cond do
      ht in loose_tiers -> true
      ht == "CHALLENGER" -> false # always reject
      ht == "MASTER" -> lr in 1..3

      # now we may can assume ht is diamond
      # we also know if hr is diamond, lt has to be platinum
      hr == 1 -> ht == lt && lr in 1..4
      hr == 2 -> false      # d2 can't queue with plat (should never be called tho)
      hr == 3 -> lr == 1    # d3 can queue with plat 1
      hr == 4 -> lr in 1..2 # d4 can queue with plat 1/2
      hr == 5 -> lr in 1..3 # d5 can queue with plat 1..3
    end
  end

  @doc """
  Returns a boolean indicating whether the given leagues are able to queue together.

  ## Examples
      iex> league1 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 1}
      iex> league2 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 2}
      iex> LolBuddy.Players.Matching.tier_compatible?(league1, league2)
      true

      iex> league3 = {type: "RANKED_SOLO_5x5", tier: "DIAMOND", rank: 1}
      iex> league4 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 2}
      iex> LolBuddy.Players.Matching.tier_compatible?(league3, league4)
      false
  """
  def tier_compatible?(league1, league2) do
    {h, l} = sort_leagues(league1, league2)
    ht = tier_to_int(h.tier)
    lt = tier_to_int(l.tier)

    # challenger's may only walk alone
    cond do
      h.tier == "CHALLENGER" -> false
      # special handling for d1 as it cannot queue with its entire league
      h.tier == "DIAMOND" && h.rank == 1 -> rank_compatible?(h, l)
      ht - lt == 0 -> true
      ht - lt == 1 -> rank_compatible?(h, l)
      true -> false
    end
  end

  @doc """
  Returns the input sorted as a tuple {high, low}
  If they are equal, league1 is returned as highest

  ## Examples
      iex> league1 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 1}
      iex> league2 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 2}
      iex> LolBuddy.Players.Matching.sort_leagues(league1, league2)
      {league1, league2}
  """
  def sort_leagues(league1, league2) do
    tier1 = tier_to_int(league1.tier)
    tier2 = tier_to_int(league2.tier)
    cond do
      tier1 > tier2 -> {league1, league2}
      tier2 > tier1 -> {league2, league1}
      true -> if (league1.rank <= league2.rank),
              do: {league1, league2},
              else: {league2, league1}
    end
  end

  defp tier_to_int(tier) do
    case tier do
      "BRONZE"     -> 1
      "SILVER"     -> 2
      "GOLD"       -> 3
      "PLATINUM"   -> 4
      "DIAMOND"    -> 5
      "MASTER"     -> 6
      "CHALLENGER" -> 7
    end
  end
end