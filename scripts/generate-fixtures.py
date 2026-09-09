"""Author synthetic presentation fixtures. Not imported or run by the application."""
import json
import statistics
from pathlib import Path
from collections import Counter

def summary(scope, title, maximum, scores):
    counts = Counter(scores)
    peak = max(counts.values())
    modes = sorted(x for x, count in counts.items() if count == peak) if peak > 1 else []
    edges = [i * (maximum + 1) / 4 for i in range(5)]
    bins = [
        dict(id=str(i), label=f"{int(edges[i] + .999999)}-{int(edges[i+1] + .999999)-1}",
             lowerBound=edges[i], upperBound=edges[i+1],
             count=sum(edges[i] <= x < edges[i+1] for x in scores))
        for i in range(4)
    ]
    return dict(id=scope, title=title, maximumScore=maximum, scores=scores,
                mean=statistics.mean(scores), median=statistics.median(scores), modes=modes,
                minimum=min(scores), maximum=max(scores), range=max(scores)-min(scores),
                populationStandardDeviation=statistics.pstdev(scores), bins=bins)

def assignment(kind, title, course, subtitle, maximum, names, prompts, responses, keys, exemplars, matrix):
    parts = [dict(id=f"{kind}-p{i+1}", title=name, maximumScore=maximum)
             for i, name in enumerate(names)]
    rubric = [dict(id=f"{kind}-c{i+1}", partID=part["id"], title=part["title"],
                   description=("Use clear reasoning and show each step." if kind=="math"
                                else "Develop the idea with precise, purposeful language."),
                   maximumScore=maximum,
                   performanceDescription=("Full credit: correct method, complete reasoning, and a supported answer."
                                           if kind=="math" else
                                           "Strong: focused claim, specific support, and a clear connection to the argument."))
              for i, part in enumerate(parts)]
    submissions=[]
    for student, scores in enumerate(matrix):
        candidate = f"Candidate {student+1:03}"
        sections=[dict(id=part["id"], heading=f"{i+1:02}  {part['title']}",
                       prompt=prompts[i], response=responses[i][student])
                  for i, part in enumerate(parts)]
        submissions.append(dict(
            id=f"{kind}-s{student+1}", candidateLabel=candidate, status="Sample draft",
            document=dict(title=title, subtitle=subtitle, sections=sections),
            exampleScore=sum(scores),
            criterionScores={criterion["id"]:score for criterion,score in zip(rubric,scores)},
            feedback=("Your approach is easy to follow. In the next draft, make the check of your result explicit."
                      if kind=="math" else
                      "Your position is clear. Connect each example back to the claim and consider an alternative view."),
            transcription="\n\n".join(s["heading"]+"\n"+s["response"] for s in sections)))
    stats=[summary("overall","Whole assignment",maximum*len(parts),[sum(row) for row in matrix])]
    stats += [summary(p["id"],p["title"],maximum,[row[i] for row in matrix]) for i,p in enumerate(parts)]
    return dict(id=kind,title=title,course=course,subtitle=subtitle,maximumScore=maximum*len(parts),
                parts=parts,submissions=submissions,rubric=rubric,
                answerKey=[dict(id=f"{kind}-key{i}",partID=p["id"],title=p["title"],body=keys[i])
                           for i,p in enumerate(parts)],
                exemplars=[dict(id=f"{kind}-ex{i}",partID=p["id"],title=p["title"],body=exemplars[i])
                           for i,p in enumerate(parts)],statistics=stats)

math = assignment(
    "math","Quadratic reasoning","Algebra II · Problem set","Show your thinking. Explain what each solution means.",5,
    ["Factor and solve","Interpret the graph","Check the solution"],
    ["Solve x² − 5x + 6 = 0 by factoring.",
     "For y = x² − 5x + 6, describe the intercepts and vertex.",
     "Substitute both roots into the original equation and explain the result."],
    [
      ["x² − 5x + 6 = (x − 2)(x − 3).\nSo x = 2 or x = 3.",
       "Two numbers multiply to 6 and add to −5: −2 and −3.\nThe factors are (x − 2)(x − 3); roots are 2 and 3.",
       "I found x = 2 by trying a value.\nI think there is another solution.",
       "(x − 2)(x − 3) = 0 gives x = 2 and x = 3.",
       "The factors are (x − 2)(x − 3).\nEach factor can equal zero: x = 2, x = 3.",
       "I factored to (x − 2)(x − 3).\nThe roots are 2 and 3."],
      ["The graph crosses the x-axis at 2 and 3.\nIt opens upward. The vertex is halfway between the roots.",
       "x-intercepts: (2, 0), (3, 0). y-intercept: (0, 6).\nThe axis is x = 2.5; vertex (2.5, −0.25).",
       "The graph opens up and crosses at x = 2.\nThe minimum is somewhere near x = 2.",
       "Intercepts are (2, 0), (3, 0), and (0, 6).\nThe vertex is at x = 2.5.",
       "Intercepts: (2, 0), (3, 0), (0, 6).\nVertex: (2.5, −0.25); the parabola opens upward.",
       "The roots are the x-intercepts.\nThe axis of symmetry is x = 2.5."],
      ["For 2: 4 − 10 + 6 = 0.\nFor 3: 9 − 15 + 6 = 0. Both satisfy the equation.",
       "2² − 5(2) + 6 = 0 and 3² − 5(3) + 6 = 0.\nBoth roots make the product zero.",
       "For x = 2, I get 4 − 10 + 6 = 0.\nThis checks one answer.",
       "At x = 2, the expression equals 0.\nAt x = 3, it also equals 0.",
       "4 − 10 + 6 = 0; 9 − 15 + 6 = 0.\nBoth solutions satisfy the original equation.",
       "I substituted 2 and got 0.\nThe factored form also gives 3."]
    ],
    ["(x − 2)(x − 3) = 0, so x = 2 or x = 3.",
     "x-intercepts (2, 0), (3, 0); y-intercept (0, 6); vertex (2.5, −0.25).",
     "At x = 2: 4 − 10 + 6 = 0. At x = 3: 9 − 15 + 6 = 0."],
    ["Name the factor pair, write the product, then use the zero-product property.",
     "Label both axes, all intercepts, and the minimum. Connect symmetry to the roots.",
     "Show both substitutions and state why a zero result verifies each root."],
    [[5,3,4],[5,5,4],[2,2,3],[4,4,4],[5,5,5],[4,3,3]]
)

writing = assignment(
    "writing","The case for green spaces","English · Written response","Make a claim, support it, and respond to another perspective.",4,
    ["Claim and focus","Evidence and reasoning","Alternative perspective"],
    ["State a clear position on adding green spaces to a city.",
     "Develop your position using an example and explain why it matters.",
     "Consider a reasonable objection and respond to it."],
    [
      ["Cities should make room for small public gardens because everyone needs a place to pause.",
       "Public green spaces should be a priority in dense neighborhoods, where private outdoor space is limited.",
       "I like parks. They are useful and cities should have them.",
       "A neighborhood park can make city life healthier and more connected.",
       "Cities should reserve land for accessible public gardens because shared outdoor space serves daily needs.",
       "Green spaces are important to people who live in apartments."],
      ["A shaded garden gives neighbors a place to meet.\nPeople can spend time outside without having to buy something.",
       "A small garden near a bus stop offers shade and seating.\nIts value comes from being part of an everyday route, not a special trip.",
       "People can play and sit at parks.\nThere are many trees.",
       "A park gives neighbors a place to meet and exercise.\nThis makes it easier to be active close to home.",
       "A courtyard garden with step-free paths can serve children, older residents, and workers on lunch breaks.\nThat range of uses makes a small area valuable.",
       "Trees provide shade and places to relax.\nIt is nice to have somewhere nearby."],
      ["Some people want the land used for parking.\nA small garden could share a block with needed parking.",
       "Land and maintenance cost money. A pilot garden on unused land lets a city test demand before expanding.",
       "Some people do not want parks.\nI still think they are good.",
       "Maintenance costs money, so cities could begin with a small space and a clear care plan.",
       "Housing is also urgent. Cities should add gardens to existing public sites where possible, protecting housing capacity while improving access.",
       "A park costs money to build.\nVolunteers could help with some tasks."]
    ],
    ["Accept a defensible, focused position. There is no single correct stance.",
     "Look for a concrete example and an explicit link to the claim. Do not infer evidence that is absent.",
     "Look for a fair objection and a reasoned response, rather than dismissal."],
    ["Shared gardens belong close to homes so residents can use them in ordinary daily life.",
     "For example, shade and seating near a transit stop turn waiting time into a chance to rest.",
     "Although land is scarce, converting an unused paved corner can improve access without replacing housing."],
    [[4,3,3],[4,4,4],[2,2,1],[3,3,3],[4,4,4],[3,2,2]]
)

out = Path(__file__).resolve().parents[1] / "Sources/WorkspaceKit/Resources/assignments.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps([math, writing], indent=2, ensure_ascii=False)+"\n")
