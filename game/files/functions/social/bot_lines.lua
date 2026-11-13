local M = rawget(_G, "social_bot_lines") or {}
social_bot_lines = M

M.FR = {
    ["Nice hand!"] = "Belle main !", ["Big one!"] = "Gros coup !", ["That felt good"] = "Ça fait du bien", ["Look at that score"] = "Regardez ce score",
    ["Boss down"] = "Boss vaincu", ["Got past the boss"] = "Boss passé", ["That boss was rough"] = "Ce boss était dur",
    ["Ouch"] = "Aïe", ["Next time"] = "La prochaine fois", ["That hurt"] = "Ça fait mal", ["Unlucky"] = "Pas de chance",
    ["Close one"] = "C'était serré", ["Phew"] = "Ouf", ["Got that one"] = "Celle-là est pour moi",
    ["Shopping time"] = "L'heure des achats", ["Nothing good in here"] = "Rien de bien ici", ["Need more money"] = "Il me faut plus d'argent",
    ["Take your time"] = "Prends ton temps", ["No rush"] = "Rien ne presse", ["Waiting on you"] = "Je t'attends",
    ["Hi!"] = "Salut !", ["Good luck"] = "Bonne chance", ["Ready when you are"] = "Prêt quand tu veux",
    ["Hey!"] = "Hé !", ["GG"] = "GG", ["GG, well played"] = "GG, bien joué", ["Haha"] = "Haha", ["Oof"] = "Ouille", ["Oops"] = "Oups",
    ["On fire"] = "En feu", ["Coming!"] = "J'arrive !", ["Almost done"] = "Presque fini", ["Lucky!"] = "Chanceux !", ["Hmm"] = "Hmm",
}

M.ES = {
    ["Nice hand!"] = "¡Buena mano!", ["Big one!"] = "¡Qué golpe!", ["That felt good"] = "Eso sentó bien", ["Look at that score"] = "Mira esa puntuación",
    ["Boss down"] = "Jefe derrotado", ["Got past the boss"] = "Superé al jefe", ["That boss was rough"] = "Ese jefe fue duro",
    ["Ouch"] = "Ay", ["Next time"] = "La próxima vez", ["That hurt"] = "Eso dolió", ["Unlucky"] = "Mala suerte",
    ["Close one"] = "Por poco", ["Phew"] = "Uf", ["Got that one"] = "Esa fue mía",
    ["Shopping time"] = "Hora de compras", ["Nothing good in here"] = "Aquí no hay nada bueno", ["Need more money"] = "Necesito más dinero",
    ["Take your time"] = "Tómate tu tiempo", ["No rush"] = "Sin prisa", ["Waiting on you"] = "Te espero",
    ["Hi!"] = "¡Hola!", ["Good luck"] = "Buena suerte", ["Ready when you are"] = "Listo cuando quieras",
    ["Hey!"] = "¡Ey!", ["GG"] = "GG", ["GG, well played"] = "GG, bien jugado", ["Haha"] = "Jaja", ["Oof"] = "Uy", ["Oops"] = "Ups",
    ["On fire"] = "En racha", ["Coming!"] = "¡Ya voy!", ["Almost done"] = "Casi termino", ["Lucky!"] = "¡Suerte!", ["Hmm"] = "Mmm",
}

function M.text(d)
    local text = tostring(d and d.text or "")
    if d and d.bot == true and M.FR[text] and mod_loc then return mod_loc(text) end
    return text
end

function M.init()
    if M.done or not mod_loc_register then return end
    M.done = true
    mod_loc_register{fr = M.FR, es = M.ES}
end

return M
