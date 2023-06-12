const jwt = require('jsonwebtoken'); // You'll need to include this dependency in your package.json

exports.handler = function(event, context, callback) {
    const token = event.authorizationToken;
    try {
        const decoded = jwt.verify(token, 'your-secret-key');
        const policy = generatePolicy(decoded.sub, 'Allow', event.methodArn);
        callback(null, policy);
    } catch (err) {
        callback("Unauthorized");
    }
}

function generatePolicy(principalId, effect, resource) {
    const policy = {
        principalId,
        policyDocument: {
            Version: '2012-10-17',
            Statement: [{
                Action: 'execute-api:Invoke',
                Effect: effect,
                Resource: resource
            }]
        }
    };
    return policy;
}
