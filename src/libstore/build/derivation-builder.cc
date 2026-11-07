#include "nix/util/json-utils.hh"
#include "nix/store/build/derivation-builder.hh"

namespace nlohmann {

nix::ExternalBuilder adl_serializer<nix::ExternalBuilder>::from_json(const json & json)
{
    using namespace nix;
    auto obj = getObject(json);
    auto optFeatures = [&](std::string_view key) -> StringSet {
        if (auto * v = optionalValueAt(obj, key))
            return v->template get<StringSet>();
        return {};
    };
    return {
        .systems = valueAt(obj, "systems"),
        .program = valueAt(obj, "program"),
        .args = valueAt(obj, "args"),
        .features = optFeatures("features"),
        .excludeFeatures = optFeatures("excludeFeatures"),
    };
}

void adl_serializer<nix::ExternalBuilder>::to_json(json & json, const nix::ExternalBuilder & eb)
{
    json = {
        {"systems", eb.systems},
        {"program", eb.program},
        {"args", eb.args},
        {"features", eb.features},
        {"excludeFeatures", eb.excludeFeatures},
    };
}

} // namespace nlohmann

namespace nix {

bool ExternalBuilder::supports(const BasicDerivation & drv, const StringSet & requiredFeatures) const
{
    if (!systems.contains(drv.platform))
        return false;

    for (auto & f : requiredFeatures)
        if (excludeFeatures.contains(f))
            return false;

    if (!features.empty())
        for (auto & f : requiredFeatures)
            if (!features.contains(f))
                return false;

    return true;
}

void BuilderFailureError::anchor() {}

void DerivationBuilder::anchor() {}

DerivationBuilderCallbacks::~DerivationBuilderCallbacks() {}

} // namespace nix
