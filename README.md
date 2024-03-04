# Moonreader
~~Totally original name~~. Yet another documentation generator for Studio. See [alternatives](#alternatives) for other options that are available.

Inspired by [Moonwave](https://github.com/evaera/moonwave), Moonreader is a simlar tool that generates documentation from the comments within your source code. The aim is to be a supplementary tool for those who work in both Studio and external editors a lot, and can also serve as a sort of "preview" for any documentation you plan on generating through Moonwave, though you can also just use Moonreader by itself if it's all you need.

Moonreader aims to be generally compliant with Moonwave's commenting syntax and support most (if not all) of its tags. See `src/Parser.lua` for the general state of how many tags are implemented.

## Usage
For a general overview of the valid syntax for doc comments, take a look at [Moonwave](https://github.com/evaera/moonwave) and its [documentation](https://eryn.io/moonwave/docs/intro).

Moonreader will automatically generate documentation from all of the source containers in the place by default. This documentation can be viewed by selecting "Open Docs" from Moonreader's plugin toolbar.

A smaller searchable version of the documentation containing only function definitions can be viewed by selecting "Quick Search". Function definitions can be jumped to by clicking on the icon next to the function name.

As of now, the only setting to change is which paths to ignore, which can be viewed and edited by selecting "Open Settings".

To regenerate the documentation, either after editing some source code or changing some settings, select "Generate Docs".

There are bindable actions to open Quick Search and to search within the documentation itself. (`File > Advanced > Customize Shortcuts...`)

## What's with all the `if game then require(...) else require("...")`?
If at all possible, I'd like to keep the dependencies I'm writing "native luau compatible",
meaning that they can work regardless of whether it's in studio or in cli (like in a runner such as lune).
Realistically I probably won't ever be using these outside of this plugin (except for maybe [IterTools](src/IterTools.lua)), but it has the big benefit
of letting me test outside of studio (particularly with all the string manipulation that's happening that doesn't necessitate testing in Studio).

## Acknowledgements
Moonreader is made possible by the brilliant projects and resources provided by these people
 - [evaera](https://github.com/evaera) and their work on Moonwave, which serves as the basis and inspiration for this project.
 - [boatbomber](https://github.com/boatbomber), [sleitnick](https://github.com/Sleitnick), and the [various others](https://github.com/boatbomber/Highlighter/blob/2890275c6bf20d00a21a2fe44f546b666e3ef530/src/lexer/init.lua#L6) who contributed towards [Highlighter](https://github.com/boatbomber/Highlighter), of which I utilize the lexer module for coloring codeblocks.

## Alternatives
 - Documentation Reader - Somewhat old but is a well-known and reliable resource
    - https://devforum.roblox.com/t/documentation-reader-a-plugin-for-scripters/128825
 - EasyDocs - Much newer, generates very nice looking documentation and does a much better job of emulating markdown.
    - https://devforum.roblox.com/t/easydocs-the-simpler-way-to-do-documentation/2321209
    - https://github.com/canary-development/EasyDocs