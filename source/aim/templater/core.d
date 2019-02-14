///
module aim.templater.core;

private
{
    import std.exception : enforce;
    import std.regex;
}

private struct TemplateConfig
{
    struct Conditional
    {
        string placeholderToTest;
        string valueToTest;
        string placeholderToMake;
        string valueToGive;
    }

    string[]        placeholders;
    Conditional[]   conditionals;
}

private void enforcePlaceholderExists(string placeholder, string[string] placeholders)
{
    enforce((placeholder in placeholders) !is null, 
            "The placeholder '"~placeholder~"' hasn't been given a value.");
}

/// A class containing static functions for templating.
static class Templater
{
    /++
     + Resolves a template, and returns the resulting string.
     +
     + Template_Format:
     +  A template starts with various config options about the template, followed by a `$FINISH_CONFIG` tag, followed by the actual template text.
     +
     +  An example of a template would be
     +
     +  ```
     +  $PLACEHOLDERS
     +      $NAME  The person's name
     +      $AGE   The person's age
     +  $END
     +  $FINISH_CONFIG
     +  Hi, my name is $NAME and I'm $AGE years old.
     +  ```
     +
     + Placeholders:
     +  Placeholders are defined using the `$PLACEHOLDER` config tag, and are ended with the `$END` tag.
     +
     +  Between the two tags are line-seperated names starting with a '$', these are placeholder names.
     +  Anything after the first space after the name is discarded, and can be used for comments.
     +
     +  The values of placeholders are defined by the `placeholders` parameter, where the name of each placeholder is used
     +  as the key.
     +
     + Conditional_Placeholders:
     +  Conditional placeholders are defined inside a `$CONDITIONAL_PLACEHOLDER` tag, and are ended with the `$END` tag.
     +
     +  Between the two tags are line-seperated entries following this format.
     +
     +  `$PLACEHOLDER_TO_TEST=SOME VALUE TO TEST $> $PLACEHOLDER_TO_MAKE=SOME VALUE TO GIVE IT`
     +
     +  Essentially, the templater will look at the value of `$PLACEHOLDER_TO_TEST`, and see if it's value
     +  is the same as `SOME VALUE TO TEST`. If it's not the same, the entry is ignored. If it is the same,
     +  then a new placeholder called `$PLACEHOLDER_TO_MAKE` is made, and is given the value `SOME VALUE TO GIVE IT`.
     +
     +  The values `SOME VALUE TO TEST` and `SOME VALUE TO GIVE IT` have whitspace stripped from the start and end.
     +
     +  Conditional placeholders are processed before normal placeholders, meaning normal placeholders can be used
     +  within the value for `$PLACEHOLDER_TO_MAKE` without issue.
     +
     + Params:
     +  placeholders = The values for all of the placeholders.
     +  data         = The template's data.
     +
     + Returns:
     +  The resolved string.
     + ++/
    static string resolveTemplate(string[string] placeholders, string data)
    {
        import std.array     : replace;
        import std.algorithm : sort;

        auto config = Templater.parseConfig(data, data);

        // Sort out conditionals
        foreach(conditional; config.conditionals)
        {
            enforcePlaceholderExists(conditional.placeholderToTest, placeholders);

            if(placeholders[conditional.placeholderToTest] == conditional.valueToTest)
            {
                placeholders[conditional.placeholderToMake] = conditional.valueToGive;
                config.placeholders ~= conditional.placeholderToMake;
            }
        }

        // Sort the placeholders by length, to solve certain issues.
        config.placeholders.sort!"a.length > b.length";

        foreach(placeholder; config.placeholders)
        {
            enforcePlaceholderExists(placeholder, placeholders);
            data = data.replace(placeholder, placeholders[placeholder]);
        }

        return data;
    }

    private static TemplateConfig parseConfig(string data, out string remaining)
    {
        // Don't worry, I hate myself for this function as well.
        import std.ascii     : isWhite;
        import std.algorithm : all, splitter, countUntil;
        import std.string    : strip;

        enum Stage
        {
            None,
            Placeholders,
            Conditionals
        }

        size_t start;
        size_t end;
        TemplateConfig config;
        Stage stage;

        while(true)
        {
            if(end >= data.length)
                throw new Exception("No $FINISH_CONFIG was found.");
            
            if(data[end] == '\n')
            {
                auto str = data[start..end].strip;
                start = end + 1;

                if(str == "" || str.all!isWhite)
                {
                    end++;
                    continue;
                }

                final switch(stage)
                {
                    case Stage.None:
                        if(str == "$PLACEHOLDERS")
                            stage = Stage.Placeholders;
                        else if(str == "$FINISH_CONFIG")
                        {
                            remaining = data[start..$];
                            return config;
                        }
                        else if(str == "$CONDITIONAL_PLACEHOLDERS")
                            stage = Stage.Conditionals;
                        break;

                    case Stage.Placeholders:
                        if(str == "$END")
                        {
                            stage = Stage.None;
                            break;
                        }

                        auto index = str.countUntil(' ');
                        config.placeholders ~= str[0..(index == -1) ? $ : index];

                        enforce(config.placeholders[$-1][0] == '$', 
                                "'"~config.placeholders[$-1]~"' is an invalid placeholder name as it does not start with a '$'");
                        break;

                    case Stage.Conditionals:
                        if(str == "$END")
                        {
                            stage = Stage.None;
                            break;
                        }

                        // [1] = PLACEHOLDER to test
                        // [2] = Value to test (must strip whitespace)
                        // [3] = PLACEHOLDER to make
                        // [4] = Value to give it (must strip whitespace)
                        auto reg    = regex(`\s*(\$[^=]+)=(.+)\$>\s*(\$[^=]+)=(.+)\r?\n?`);
                        auto result = str.matchFirst(reg);
                        enforce(!result.empty, "Invalid CONDITIONAL_PLACEHOLDER line: '"~str~"'");

                        config.conditionals ~= TemplateConfig.Conditional(result[1], result[2].strip(), result[3], result[4].strip());
                        break;
                }
            }

            end++;
        }
    }
}
///
unittest
{
    auto templ = `
    $PLACEHOLDERS
        $NAME   The person's name
        $AGE    The persno's age
        $GENDER The person's gender
    $END
    $CONDITIONAL_PLACEHOLDERS
        $GENDER=Male   $> $GENDER_TEXT=I'm a man
        $GENDER=Female $> $GENDER_TEXT=I'm a woman
    $END
    $FINISH_CONFIG
    Hi, my name is $NAME, I'm $AGE years old, and $GENDER_TEXT.`;

    auto data = 
    [
        "$NAME":    "Bob",
        "$AGE":     "69",
        "$GENDER":  "Male"
    ];
    assert(Templater.resolveTemplate(data, templ) == "    Hi, my name is Bob, I'm 69 years old, and I'm a man.");

    data = 
    [
        "$NAME":    "Susie",
        "$AGE":     "20",
        "$GENDER":  "Female"
    ];
    assert(Templater.resolveTemplate(data, templ) == "    Hi, my name is Susie, I'm 20 years old, and I'm a woman.");
}