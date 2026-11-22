"""The wanted list for the gather step: wanted.json, written by teach_feedback.py, names episodes
where the phone's notes showed a miss or a taken-back skip. teach_collect.py plans those before the
newest episodes of each show.

Standard library only. No network: this module reads wanted.json and picks episodes out of feeds
that teach_collect.py has already fetched.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

from teach_feed import episode_id, feed_key, is_web_address

WANTED = "wanted.json"
MOST = 20


def usable(item):
    """True when a wanted entry names a feed and an episode (by guid or audio address)."""
    return (isinstance(item, dict) and isinstance(item.get("feed"), str) and item["feed"]
            and isinstance(item.get("guid"), str) and isinstance(item.get("address"), str)
            and isinstance(item.get("title"), str) and (item["guid"] or item["address"]))


def load_wanted(folder, say):
    """The usable entries of <folder>/wanted.json, in file order. No file means nothing is wanted.
    A file that is damaged is ignored with one line."""
    path = os.path.join(folder, WANTED)
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        if not isinstance(data, dict) or data.get("version") != 1 \
                or not isinstance(data.get("episodes"), list):
            raise ValueError("it is not a version 1 list")
    except (OSError, ValueError) as error:
        say("The list of wanted episodes in %s is damaged (%s), so it was ignored." % (path, error))
        return []
    return [item for item in data["episodes"] if usable(item)]


def followed_only(wanted, shows, say):
    """The wanted entries whose feed is a followed show (matched by feed key), each with that show's
    own feed address. Entries with an address that is not http or https, or whose feed is not
    followed, are counted and left out with one line."""
    own = {}
    for show in shows:
        own.setdefault(feed_key(show["feed"]), show["feed"])
    kept, unsafe, unfollowed = [], 0, 0
    for item in wanted:
        if not is_web_address(item["feed"]) or (item["address"] and not is_web_address(item["address"])):
            unsafe += 1
        elif feed_key(item["feed"]) not in own:
            unfollowed += 1
        else:
            kept.append(dict(item, feed=own[feed_key(item["feed"])]))
    if unsafe:
        say("Left out %d wanted episode%s whose address is not an http or https address."
            % (unsafe, "" if unsafe == 1 else "s"))
    if unfollowed:
        say("Left out %d wanted episode%s whose feed is not one of the shows you follow."
            % (unfollowed, "" if unfollowed == 1 else "s"))
    return kept


def find(episodes, item):
    """The episode of a feed that a wanted entry means: by guid, or by audio address when the entry
    has no guid. None when the feed no longer lists it."""
    for episode in episodes:
        if (episode["guid"] == item["guid"]) if item["guid"] else (episode["address"] == item["address"]):
            return episode
    return None


def wanted_entries(wanted, feeds, known_ids, most, say, make):
    """The new entries for the wanted episodes, in the order of the list, at most `most`. `feeds`
    maps a feed address to (show title, all its episodes), or to None when it could not be read;
    `make(title, feed, episode)` builds an entry. An episode that is already known or already
    planned is left out quietly, one that the feed no longer lists with one line, and one whose
    feed could not be read with one line. Those left out do not count towards `most`."""
    entries, taken = [], set(known_ids)
    for item in wanted:
        if len(entries) >= most:
            break
        name = item["title"] or item["address"] or item["guid"]
        found = feeds.get(item["feed"])
        if found is None:
            say("Skipped the wanted episode \"%s\": its feed could not be read." % name)
            continue
        episode = find(found[1], item)
        if episode is None:
            say("Skipped the wanted episode \"%s\": it is no longer in its feed." % name)
            continue
        if episode_id(item["feed"], episode["guid"], episode["address"]) in taken:
            continue
        entry = make(found[0], item["feed"], episode)
        taken.add(entry["id"])
        entries.append(entry)
    return entries
