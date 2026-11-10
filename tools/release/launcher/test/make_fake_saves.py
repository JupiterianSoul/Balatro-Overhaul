import os
import sys
import zlib


def jkr(text):
    c = zlib.compressobj(1, zlib.DEFLATED, -15)
    return c.compress(text.encode()) + c.flush()


def profile(name, wins, rounds):
    return ('return {["name"]="%s",["career_stats"]={["c_wins"]=%d,["c_rounds"]=%d,["c_hands_played"]=%d},'
            '["high_scores"]={["most_money"]={["amt"]=%d}},["progress"]={}}' % (name, wins, rounds, rounds * 4, wins * 10))


def meta():
    return 'return {["unlocked"]={["j_joker"]=true,["j_blueprint"]=true},["discovered"]={["j_joker"]=true},["alerted"]={}}'


def write_save(root, profiles):
    for slot, (name, wins, rounds) in profiles.items():
        d = os.path.join(root, str(slot))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "profile.jkr"), "wb") as f:
            f.write(jkr(profile(name, wins, rounds)))
        with open(os.path.join(d, "meta.jkr"), "wb") as f:
            f.write(jkr(meta()))
        with open(os.path.join(d, "save.jkr"), "wb") as f:
            f.write(jkr('return {["GAME"]={["round"]=3}}'))
    with open(os.path.join(root, "settings.jkr"), "wb") as f:
        f.write(jkr('return {["profile"]=1,["language"]="en-us"}'))


def main():
    home = sys.argv[1]
    proton = os.path.join(home, ".local/share/Steam/steamapps/compatdata/2379780/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro")
    write_save(proton, {1: ("P1", 12, 140), 2: ("Gab", 3, 51)})
    other = os.path.join(home, "other_save/Balatro")
    write_save(other, {1: ("Old", 1, 9)})
    print(proton)
    print(other)


if __name__ == "__main__":
    main()
