exports.handler = async (event) => {
  return {
    statusCode: 200,
    body: JSON.stringify({ 
      message: "Send Email Lambda - Not implemented yet",
      function: "send-email",
      emailSent: false
    })
  };
};